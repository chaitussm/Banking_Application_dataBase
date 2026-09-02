#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-banking.sqlite}"
REPORT_PATH="${2:-reports/db-health-report.md}"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Error: sqlite3 is required but not installed." >&2
  exit 1
fi

if [[ ! -f "${DB_PATH}" ]]; then
  echo "Error: database file not found at ${DB_PATH}" >&2
  echo "Run: make db-init DB_FILE=${DB_PATH}" >&2
  exit 1
fi

report_dir="$(dirname "${REPORT_PATH}")"
mkdir -p "${report_dir}"

generated_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
generated_local="$(date +"%B %d, %Y at %H:%M %Z")"

users_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM users;")"
accounts_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM accounts;")"
transactions_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM transactions;")"
refresh_tokens_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM refresh_tokens;")"

orphan_accounts="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM accounts a LEFT JOIN users u ON u.id = a.user_id WHERE u.id IS NULL;")"
orphan_transactions="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM transactions t LEFT JOIN accounts a ON a.id = t.account_id WHERE a.id IS NULL;")"

latest_transactions="$(sqlite3 -noheader "${DB_PATH}" "SELECT id || ' | ' || account_id || ' | ' || kind || ' | ' || amount || ' | ' || COALESCE(note, '') || ' | ' || timestamp FROM transactions ORDER BY timestamp DESC LIMIT 5;")"

sqlite_version="$(sqlite3 "${DB_PATH}" "SELECT sqlite_version();")"
foreign_keys_enabled="$(sqlite3 "${DB_PATH}" "PRAGMA foreign_keys;")"
table_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")"
index_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';")"
db_size_bytes="$(wc -c < "${DB_PATH}" | tr -d ' ')"
total_balance="$(sqlite3 "${DB_PATH}" "SELECT COALESCE(ROUND(SUM(balance), 2), 0) FROM accounts;")"
credit_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM transactions WHERE kind='credit';")"
debit_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM transactions WHERE kind='debit';")"
customer_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM users WHERE role='customer';")"
manager_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM users WHERE role='manager';")"

schema_tables="$(sqlite3 -noheader "${DB_PATH}" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")"

pipeline_workflow="${GITHUB_WORKFLOW:-}"
pipeline_run_id="${GITHUB_RUN_ID:-}"
pipeline_run_url=""
if [[ -n "${pipeline_run_id}" && -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  pipeline_run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${pipeline_run_id}"
fi

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

format_bytes() {
  local bytes="$1"
  if [[ "${bytes}" -lt 1024 ]]; then
    printf '%s B' "${bytes}"
  elif [[ "${bytes}" -lt 1048576 ]]; then
    printf '%.1f KB' "$(awk "BEGIN {print ${bytes}/1024}")"
  else
    printf '%.2f MB' "$(awk "BEGIN {print ${bytes}/1048576}")"
  fi
}

verification_pass="true"
verification_notes=()

if [[ "${users_count}" -lt 3 ]]; then
  verification_pass="false"
  verification_notes+=("Expected at least 3 users, found ${users_count}")
fi
if [[ "${accounts_count}" -lt 3 ]]; then
  verification_pass="false"
  verification_notes+=("Expected at least 3 accounts, found ${accounts_count}")
fi
if [[ "${transactions_count}" -lt 3 ]]; then
  verification_pass="false"
  verification_notes+=("Expected at least 3 transactions, found ${transactions_count}")
fi
if [[ "${orphan_accounts}" != "0" ]]; then
  verification_pass="false"
  verification_notes+=("Found ${orphan_accounts} orphan account(s)")
fi
if [[ "${orphan_transactions}" != "0" ]]; then
  verification_pass="false"
  verification_notes+=("Found ${orphan_transactions} orphan transaction(s)")
fi

write_markdown_report() {
  echo "# Database Health Report"
  echo
  echo "- Generated UTC: ${generated_utc}"
  echo "- Database: ${DB_PATH}"
  echo
  echo "## Row Counts"
  echo
  echo "| Table | Rows |"
  echo "|---|---:|"
  echo "| users | ${users_count} |"
  echo "| accounts | ${accounts_count} |"
  echo "| transactions | ${transactions_count} |"
  echo "| refresh_tokens | ${refresh_tokens_count} |"
  echo
  echo "## Integrity Checks"
  echo
  echo "| Check | Value | Status |"
  echo "|---|---:|---|"

  if [[ "${orphan_accounts}" == "0" ]]; then
    echo "| Orphan accounts (no matching user) | ${orphan_accounts} | PASS |"
  else
    echo "| Orphan accounts (no matching user) | ${orphan_accounts} | FAIL |"
  fi

  if [[ "${orphan_transactions}" == "0" ]]; then
    echo "| Orphan transactions (no matching account) | ${orphan_transactions} | PASS |"
  else
    echo "| Orphan transactions (no matching account) | ${orphan_transactions} | FAIL |"
  fi

  echo
  echo "## Latest Transactions (Top 5)"
  echo
  echo "| id | account_id | kind | amount | timestamp |"
  echo "|---|---|---|---:|---|"

  if [[ -n "${latest_transactions}" ]]; then
    while IFS= read -r line; do
      id="$(echo "${line}" | cut -d '|' -f 1 | xargs)"
      account_id="$(echo "${line}" | cut -d '|' -f 2 | xargs)"
      kind="$(echo "${line}" | cut -d '|' -f 3 | xargs)"
      amount="$(echo "${line}" | cut -d '|' -f 4 | xargs)"
      timestamp="$(echo "${line}" | cut -d '|' -f 6- | xargs)"
      echo "| ${id} | ${account_id} | ${kind} | ${amount} | ${timestamp} |"
    done <<< "${latest_transactions}"
  else
    echo "| - | - | - | - | - |"
  fi
}

write_html_report() {
  local overall_status="Healthy"
  local status_class="pass"
  local verification_status="PASS"
  local verification_class="pass"
  local fk_status="Disabled"
  local fk_class="fail"
  local db_size_human
  local schema_rows=""
  local verification_detail_rows=""

  db_size_human="$(format_bytes "${db_size_bytes}")"

  if [[ "${orphan_accounts}" != "0" || "${orphan_transactions}" != "0" ]]; then
    overall_status="Needs attention"
    status_class="fail"
  fi

  if [[ "${verification_pass}" == "true" ]]; then
    verification_status="All checks passed"
  else
    verification_status="Verification failed"
    verification_class="fail"
    overall_status="Needs attention"
    status_class="fail"
  fi

  if [[ "${foreign_keys_enabled}" == "1" ]]; then
    fk_status="Enabled"
    fk_class="pass"
  fi

  while IFS= read -r table_name; do
    [[ -z "${table_name}" ]] && continue
    schema_rows="${schema_rows}        <tr><td><code>$(html_escape "${table_name}")</code></td><td>Core banking entity</td></tr>\n"
  done <<< "${schema_tables}"

  if [[ "${#verification_notes[@]}" -eq 0 ]]; then
    verification_detail_rows='        <tr><td colspan="2">All minimum thresholds and referential integrity checks passed.</td></tr>'
  else
    for note in "${verification_notes[@]}"; do
      verification_detail_rows="${verification_detail_rows}        <tr><td colspan=\"2\">$(html_escape "${note}")</td></tr>\n"
    done
  fi

  cat <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <title>Database Health Report</title>
  <style>
    :root {
      color-scheme: light dark;
      --ink: #0b1220;
      --ink-soft: #334155;
      --ink-muted: #64748b;
      --surface: #ffffff;
      --surface-raised: #f8fafc;
      --line: #e2e8f0;
      --canvas: #eef2ff;
      --brand-900: #0f172a;
      --brand-700: #1d4ed8;
      --brand-500: #3b82f6;
      --brand-100: #dbeafe;
      --green: #047857;
      --green-soft: #ecfdf5;
      --red: #b91c1c;
      --red-soft: #fef2f2;
      --amber: #b45309;
      --amber-soft: #fffbeb;
      --shadow: 0 18px 45px rgba(15, 23, 42, 0.12);
      --radius-lg: 20px;
      --radius-md: 14px;
      --radius-sm: 10px;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --ink: #e2e8f0;
        --ink-soft: #cbd5e1;
        --ink-muted: #94a3b8;
        --surface: #111827;
        --surface-raised: #0f172a;
        --line: #1f2937;
        --canvas: #020617;
        --brand-100: #1e3a8a;
        --green-soft: #052e16;
        --red-soft: #450a0a;
        --amber-soft: #451a03;
        --shadow: 0 18px 45px rgba(0, 0, 0, 0.45);
      }
    }

    * { box-sizing: border-box; }
    body {
      margin: 0;
      background:
        radial-gradient(circle at top left, rgba(59, 130, 246, 0.18), transparent 28%),
        radial-gradient(circle at top right, rgba(14, 165, 233, 0.12), transparent 24%),
        var(--canvas);
      color: var(--ink);
      font-family: "Segoe UI", ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
      line-height: 1.55;
    }

    .container { width: min(1180px, calc(100% - 32px)); margin: 0 auto; }
    header {
      position: relative;
      overflow: hidden;
      padding: 56px 0 88px;
      color: #fff;
      background: linear-gradient(135deg, #0f172a 0%, #1e3a8a 48%, #2563eb 100%);
    }
    header::after {
      content: "";
      position: absolute;
      inset: auto -10% -45% auto;
      width: 420px;
      height: 420px;
      border-radius: 50%;
      background: rgba(255, 255, 255, 0.08);
      filter: blur(0);
    }
    .hero-grid {
      position: relative;
      z-index: 1;
      display: grid;
      grid-template-columns: 1.4fr 0.9fr;
      gap: 28px;
      align-items: end;
    }
    .eyebrow {
      margin: 0 0 10px;
      color: #bfdbfe;
      font-size: 0.78rem;
      font-weight: 700;
      letter-spacing: 0.14em;
      text-transform: uppercase;
    }
    h1 {
      margin: 0;
      font-size: clamp(2.2rem, 5vw, 3.4rem);
      line-height: 1.05;
      letter-spacing: -0.03em;
    }
    .subtitle {
      max-width: 640px;
      margin: 18px 0 0;
      color: #dbeafe;
      font-size: 1.05rem;
    }
    .hero-card {
      padding: 22px 24px;
      border: 1px solid rgba(255, 255, 255, 0.18);
      border-radius: var(--radius-lg);
      background: rgba(15, 23, 42, 0.35);
      backdrop-filter: blur(10px);
    }
    .hero-card p { margin: 0 0 8px; color: #dbeafe; font-size: 0.82rem; text-transform: uppercase; letter-spacing: 0.08em; }
    .hero-card strong { display: block; font-size: 1.8rem; line-height: 1.1; }
    .metadata {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 28px;
    }
    .chip {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.12);
      color: #eff6ff;
      font-size: 0.86rem;
    }
    main { padding: 0 0 56px; }
    .status-panel {
      display: grid;
      grid-template-columns: 1.2fr 0.8fr;
      gap: 18px;
      margin-top: -42px;
      position: relative;
      z-index: 2;
    }
    .panel {
      padding: 24px;
      border: 1px solid var(--line);
      border-radius: var(--radius-lg);
      background: var(--surface);
      box-shadow: var(--shadow);
    }
    .panel h2, section h2 {
      margin: 0 0 16px;
      font-size: 1.15rem;
      letter-spacing: -0.02em;
    }
    .status-label {
      margin: 0 0 6px;
      color: var(--ink-muted);
      font-size: 0.84rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .status-value {
      margin: 0;
      font-size: 1.85rem;
      font-weight: 800;
      letter-spacing: -0.03em;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 14px;
      border-radius: 999px;
      font-size: 0.82rem;
      font-weight: 800;
      letter-spacing: 0.04em;
      text-transform: uppercase;
    }
    .badge::before {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      content: "";
      background: currentColor;
      box-shadow: 0 0 0 4px currentColor;
      opacity: 0.18;
    }
    .pass { color: var(--green); background: var(--green-soft); }
    .fail { color: var(--red); background: var(--red-soft); }
    .warn { color: var(--amber); background: var(--amber-soft); }
    .grid-2, .grid-3, .grid-4 {
      display: grid;
      gap: 16px;
    }
    .grid-2 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .grid-3 { grid-template-columns: repeat(3, minmax(0, 1fr)); }
    .grid-4 { grid-template-columns: repeat(4, minmax(0, 1fr)); }
    section { margin-top: 28px; }
    .card, .table-wrap {
      border: 1px solid var(--line);
      border-radius: var(--radius-md);
      background: var(--surface);
      box-shadow: 0 8px 24px rgba(15, 23, 42, 0.05);
    }
    .card {
      padding: 20px;
      min-height: 118px;
    }
    .card .label {
      margin: 0;
      color: var(--ink-muted);
      font-size: 0.82rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .card .value {
      display: block;
      margin-top: 10px;
      font-size: 2rem;
      font-weight: 800;
      line-height: 1;
      letter-spacing: -0.03em;
    }
    .card .hint {
      display: block;
      margin-top: 10px;
      color: var(--ink-soft);
      font-size: 0.88rem;
    }
    .table-wrap { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; text-align: left; }
    th, td {
      padding: 14px 18px;
      border-bottom: 1px solid var(--line);
      vertical-align: top;
    }
    th {
      color: var(--ink-muted);
      background: var(--surface-raised);
      font-size: 0.74rem;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      white-space: nowrap;
    }
    tr:last-child td { border-bottom: 0; }
    .numeric { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
    .kind-pill {
      display: inline-flex;
      padding: 4px 10px;
      border-radius: 999px;
      font-size: 0.78rem;
      font-weight: 800;
      letter-spacing: 0.05em;
      text-transform: uppercase;
    }
    .kind-credit { color: var(--green); background: var(--green-soft); }
    .kind-debit { color: var(--red); background: var(--red-soft); }
    code {
      padding: 2px 6px;
      border-radius: 6px;
      background: var(--surface-raised);
      font-size: 0.92em;
    }
    .link {
      color: var(--brand-500);
      text-decoration: none;
      font-weight: 600;
    }
    .link:hover { text-decoration: underline; }
    footer {
      padding: 28px 0 36px;
      border-top: 1px solid var(--line);
      color: var(--ink-muted);
      font-size: 0.88rem;
    }
    @media (max-width: 900px) {
      .hero-grid, .status-panel, .grid-4, .grid-3, .grid-2 { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <header>
    <div class="container hero-grid">
      <div>
        <p class="eyebrow">Banking database observability</p>
        <h1>Database Health Report</h1>
        <p class="subtitle">A polished snapshot of schema health, data volume, referential integrity, and recent ledger activity for the banking framework.</p>
        <div class="metadata">
          <span class="chip">Generated $(html_escape "${generated_utc}")</span>
          <span class="chip">Database $(html_escape "${DB_PATH}")</span>
          <span class="chip">SQLite $(html_escape "${sqlite_version}")</span>
        </div>
      </div>
      <div class="hero-card">
        <p>Total account balance</p>
        <strong>\$$(html_escape "${total_balance}")</strong>
      </div>
    </div>
  </header>

  <main class="container">
    <div class="status-panel">
      <article class="panel">
        <p class="status-label">Overall database health</p>
        <p class="status-value">${overall_status}</p>
        <p class="subtitle" style="margin-top:12px;color:var(--ink-soft);font-size:0.95rem;">Report prepared on $(html_escape "${generated_local}")</p>
      </article>
      <article class="panel">
        <p class="status-label">Verification summary</p>
        <p class="status-value" style="font-size:1.35rem;">${verification_status}</p>
        <div style="margin-top:16px;display:flex;gap:10px;flex-wrap:wrap;">
          <span class="badge ${status_class}">${overall_status}</span>
          <span class="badge ${verification_class}">${verification_status}</span>
        </div>
      </article>
    </div>

    <section>
      <h2>Database Metadata</h2>
      <div class="grid-4">
        <article class="card"><p class="label">File size</p><span class="value">$(html_escape "${db_size_human}")</span><span class="hint">${db_size_bytes} bytes</span></article>
        <article class="card"><p class="label">Tables</p><span class="value">${table_count}</span><span class="hint">Core schema objects</span></article>
        <article class="card"><p class="label">Indexes</p><span class="value">${index_count}</span><span class="hint">Query acceleration</span></article>
        <article class="card"><p class="label">Foreign keys</p><span class="value">${fk_status}</span><span class="hint"><span class="badge ${fk_class}">${fk_status}</span></span></article>
      </div>
    </section>

    <section>
      <h2>Row Counts</h2>
      <div class="grid-4">
        <article class="card"><p class="label">Users</p><span class="value">${users_count}</span><span class="hint">${customer_count} customers · ${manager_count} managers</span></article>
        <article class="card"><p class="label">Accounts</p><span class="value">${accounts_count}</span><span class="hint">Linked to user identities</span></article>
        <article class="card"><p class="label">Transactions</p><span class="value">${transactions_count}</span><span class="hint">${credit_count} credits · ${debit_count} debits</span></article>
        <article class="card"><p class="label">Refresh Tokens</p><span class="value">${refresh_tokens_count}</span><span class="hint">Active session records</span></article>
      </div>
    </section>

    <section>
      <h2>Integrity Checks</h2>
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>Check</th><th class="numeric">Value</th><th>Status</th></tr>
          </thead>
          <tbody>
            <tr>
              <td>Orphan accounts (no matching user)</td>
              <td class="numeric">${orphan_accounts}</td>
              <td><span class="badge $(if [[ "${orphan_accounts}" == "0" ]]; then echo pass; else echo fail; fi)">$(if [[ "${orphan_accounts}" == "0" ]]; then echo PASS; else echo FAIL; fi)</span></td>
            </tr>
            <tr>
              <td>Orphan transactions (no matching account)</td>
              <td class="numeric">${orphan_transactions}</td>
              <td><span class="badge $(if [[ "${orphan_transactions}" == "0" ]]; then echo pass; else echo fail; fi)">$(if [[ "${orphan_transactions}" == "0" ]]; then echo PASS; else echo FAIL; fi)</span></td>
            </tr>
            <tr>
              <td>Minimum seeded users (>= 3)</td>
              <td class="numeric">${users_count}</td>
              <td><span class="badge $(if [[ "${users_count}" -ge 3 ]]; then echo pass; else echo fail; fi)">$(if [[ "${users_count}" -ge 3 ]]; then echo PASS; else echo FAIL; fi)</span></td>
            </tr>
            <tr>
              <td>Minimum seeded accounts (>= 3)</td>
              <td class="numeric">${accounts_count}</td>
              <td><span class="badge $(if [[ "${accounts_count}" -ge 3 ]]; then echo pass; else echo fail; fi)">$(if [[ "${accounts_count}" -ge 3 ]]; then echo PASS; else echo FAIL; fi)</span></td>
            </tr>
            <tr>
              <td>Minimum seeded transactions (>= 3)</td>
              <td class="numeric">${transactions_count}</td>
              <td><span class="badge $(if [[ "${transactions_count}" -ge 3 ]]; then echo pass; else echo fail; fi)">$(if [[ "${transactions_count}" -ge 3 ]]; then echo PASS; else echo FAIL; fi)</span></td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section>
      <h2>Schema Overview</h2>
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>Table</th><th>Description</th></tr>
          </thead>
          <tbody>
$(printf '%b' "${schema_rows}")
          </tbody>
        </table>
      </div>
    </section>

    <section>
      <h2>Latest Transactions</h2>
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>ID</th><th>Account ID</th><th>Kind</th><th class="numeric">Amount</th><th>Note</th><th>Timestamp</th></tr>
          </thead>
          <tbody>
EOF

  if [[ -n "${latest_transactions}" ]]; then
    while IFS= read -r line; do
      id="$(echo "${line}" | cut -d '|' -f 1 | xargs)"
      account_id="$(echo "${line}" | cut -d '|' -f 2 | xargs)"
      kind="$(echo "${line}" | cut -d '|' -f 3 | xargs)"
      amount="$(echo "${line}" | cut -d '|' -f 4 | xargs)"
      note="$(echo "${line}" | cut -d '|' -f 5 | xargs)"
      timestamp="$(echo "${line}" | cut -d '|' -f 6- | xargs)"
      kind_class="kind-credit"
      if [[ "${kind}" == "debit" ]]; then
        kind_class="kind-debit"
      fi
      printf '            <tr><td><code>%s</code></td><td><code>%s</code></td><td><span class="kind-pill %s">%s</span></td><td class="numeric">%s</td><td>%s</td><td>%s</td></tr>\n' \
        "$(html_escape "${id}")" "$(html_escape "${account_id}")" "${kind_class}" "$(html_escape "${kind}")" "$(html_escape "${amount}")" "$(html_escape "${note}")" "$(html_escape "${timestamp}")"
    done <<< "${latest_transactions}"
  else
    echo '            <tr><td colspan="6">No transactions found.</td></tr>'
  fi

  cat <<EOF
          </tbody>
        </table>
      </div>
    </section>

    <section>
      <h2>Verification Notes</h2>
      <div class="table-wrap">
        <table>
          <tbody>
${verification_detail_rows}
          </tbody>
        </table>
      </div>
    </section>
EOF

  if [[ -n "${pipeline_workflow}" ]]; then
    cat <<EOF

    <section>
      <h2>Pipeline Context</h2>
      <div class="grid-2">
        <article class="card"><p class="label">Workflow</p><span class="value" style="font-size:1.2rem;">$(html_escape "${pipeline_workflow}")</span></article>
        <article class="card"><p class="label">Run</p><span class="value" style="font-size:1.2rem;">#$(html_escape "${pipeline_run_id}")</span>
EOF
    if [[ -n "${pipeline_run_url}" ]]; then
      cat <<EOF
          <span class="hint"><a class="link" href="$(html_escape "${pipeline_run_url}")">Open workflow run</a></span>
EOF
    fi
    cat <<EOF
        </article>
      </div>
    </section>
EOF
  fi

  cat <<'EOF'
  </main>
  <footer>
    <div class="container">Generated automatically by the Banking Database Pipeline. Download the HTML artifact for a fully self-contained report.</div>
  </footer>
</body>
</html>
EOF
}

case "${REPORT_PATH}" in
  *.md)
    write_markdown_report > "${REPORT_PATH}"
    ;;
  *.html|*.htm)
    write_html_report > "${REPORT_PATH}"
    ;;
  *)
    echo "Error: report path must use a .md, .html, or .htm extension: ${REPORT_PATH}" >&2
    exit 1
    ;;
esac

echo "Report generated at ${REPORT_PATH}"
