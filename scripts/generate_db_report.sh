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

users_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM users;")"
accounts_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM accounts;")"
transactions_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM transactions;")"
refresh_tokens_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM refresh_tokens;")"

orphan_accounts="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM accounts a LEFT JOIN users u ON u.id = a.user_id WHERE u.id IS NULL;")"
orphan_transactions="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM transactions t LEFT JOIN accounts a ON a.id = t.account_id WHERE a.id IS NULL;")"

latest_transactions="$(sqlite3 -noheader "${DB_PATH}" "SELECT id || ' | ' || account_id || ' | ' || kind || ' | ' || amount || ' | ' || timestamp FROM transactions ORDER BY timestamp DESC LIMIT 5;")"

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

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
      timestamp="$(echo "${line}" | cut -d '|' -f 5- | xargs)"
      echo "| ${id} | ${account_id} | ${kind} | ${amount} | ${timestamp} |"
    done <<< "${latest_transactions}"
  else
    echo "| - | - | - | - | - |"
  fi
}

write_html_report() {
  local overall_status="Healthy"
  local status_class="pass"

  if [[ "${orphan_accounts}" != "0" || "${orphan_transactions}" != "0" ]]; then
    overall_status="Needs attention"
    status_class="fail"
  fi

  cat <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Database Health Report</title>
  <style>
    :root { color-scheme: light; --navy: #0f172a; --blue: #2563eb; --blue-soft: #eff6ff; --green: #15803d; --green-soft: #f0fdf4; --red: #b91c1c; --red-soft: #fef2f2; --slate: #475569; --line: #e2e8f0; --surface: #ffffff; --canvas: #f8fafc; }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--canvas); color: var(--navy); font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.5; }
    .container { width: min(1120px, calc(100% - 32px)); margin: 0 auto; }
    header { padding: 48px 0 64px; color: #fff; background: linear-gradient(120deg, #0f172a, #1d4ed8); }
    .eyebrow { margin: 0 0 8px; color: #bfdbfe; font-size: .78rem; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; }
    h1 { margin: 0; font-size: clamp(2rem, 5vw, 3.25rem); line-height: 1.1; }
    .subtitle { max-width: 680px; margin: 16px 0 0; color: #dbeafe; font-size: 1.05rem; }
    .metadata { display: flex; flex-wrap: wrap; gap: 12px 24px; margin-top: 28px; color: #e0e7ff; font-size: .9rem; }
    main { padding: 0 0 48px; }
    .status-panel { display: flex; align-items: center; justify-content: space-between; gap: 20px; margin-top: -32px; padding: 24px; border: 1px solid var(--line); border-radius: 16px; background: var(--surface); box-shadow: 0 12px 30px rgba(15, 23, 42, .10); }
    .status-label { margin: 0 0 4px; color: var(--slate); font-size: .875rem; font-weight: 600; }
    .status-value { margin: 0; font-size: 1.5rem; font-weight: 750; }
    .badge { display: inline-flex; align-items: center; gap: 8px; padding: 8px 14px; border-radius: 999px; font-size: .875rem; font-weight: 700; }
    .badge::before { width: 8px; height: 8px; border-radius: 50%; content: ""; background: currentColor; }
    .pass { color: var(--green); background: var(--green-soft); }
    .fail { color: var(--red); background: var(--red-soft); }
    section { margin-top: 40px; }
    h2 { margin: 0 0 16px; font-size: 1.25rem; }
    .cards { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; }
    .card, .table-wrap { border: 1px solid var(--line); border-radius: 12px; background: var(--surface); }
    .card { padding: 20px; }
    .card p { margin: 0; color: var(--slate); font-size: .875rem; font-weight: 600; }
    .card strong { display: block; margin-top: 8px; font-size: 2rem; line-height: 1; }
    .table-wrap { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; text-align: left; }
    th, td { padding: 14px 18px; border-bottom: 1px solid var(--line); white-space: nowrap; }
    th { color: var(--slate); background: #f8fafc; font-size: .75rem; letter-spacing: .06em; text-transform: uppercase; }
    tr:last-child td { border-bottom: 0; }
    .numeric { text-align: right; font-variant-numeric: tabular-nums; }
    .result { font-size: .8rem; font-weight: 750; }
    footer { padding: 24px 0; border-top: 1px solid var(--line); color: var(--slate); font-size: .85rem; }
    @media (max-width: 760px) { .cards { grid-template-columns: repeat(2, minmax(0, 1fr)); } .status-panel { align-items: flex-start; flex-direction: column; } }
    @media (max-width: 420px) { .cards { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <header>
    <div class="container">
      <p class="eyebrow">Banking database observability</p>
      <h1>Database Health Report</h1>
      <p class="subtitle">A compact view of database volume, referential integrity, and the most recent ledger activity.</p>
      <div class="metadata"><span>Generated: $(html_escape "${generated_utc}")</span><span>Database: $(html_escape "${DB_PATH}")</span></div>
    </div>
  </header>
  <main class="container">
    <div class="status-panel">
      <div><p class="status-label">Overall database health</p><p class="status-value">${overall_status}</p></div>
      <span class="badge ${status_class}">${overall_status}</span>
    </div>
    <section>
      <h2>Row Counts</h2>
      <div class="cards">
        <article class="card"><p>Users</p><strong>${users_count}</strong></article>
        <article class="card"><p>Accounts</p><strong>${accounts_count}</strong></article>
        <article class="card"><p>Transactions</p><strong>${transactions_count}</strong></article>
        <article class="card"><p>Refresh Tokens</p><strong>${refresh_tokens_count}</strong></article>
      </div>
    </section>
    <section>
      <h2>Integrity Checks</h2>
      <div class="table-wrap"><table><thead><tr><th>Check</th><th class="numeric">Value</th><th>Status</th></tr></thead><tbody>
        <tr><td>Orphan accounts (no matching user)</td><td class="numeric">${orphan_accounts}</td><td><span class="badge $(if [[ "${orphan_accounts}" == "0" ]]; then echo pass; else echo fail; fi)">$(if [[ "${orphan_accounts}" == "0" ]]; then echo PASS; else echo FAIL; fi)</span></td></tr>
        <tr><td>Orphan transactions (no matching account)</td><td class="numeric">${orphan_transactions}</td><td><span class="badge $(if [[ "${orphan_transactions}" == "0" ]]; then echo pass; else echo fail; fi)">$(if [[ "${orphan_transactions}" == "0" ]]; then echo PASS; else echo FAIL; fi)</span></td></tr>
      </tbody></table></div>
    </section>
    <section>
      <h2>Latest Transactions</h2>
      <div class="table-wrap"><table><thead><tr><th>ID</th><th>Account ID</th><th>Kind</th><th class="numeric">Amount</th><th>Timestamp</th></tr></thead><tbody>
EOF

  if [[ -n "${latest_transactions}" ]]; then
    while IFS= read -r line; do
      id="$(echo "${line}" | cut -d '|' -f 1 | xargs)"
      account_id="$(echo "${line}" | cut -d '|' -f 2 | xargs)"
      kind="$(echo "${line}" | cut -d '|' -f 3 | xargs)"
      amount="$(echo "${line}" | cut -d '|' -f 4 | xargs)"
      timestamp="$(echo "${line}" | cut -d '|' -f 5- | xargs)"
      printf '        <tr><td>%s</td><td>%s</td><td>%s</td><td class="numeric">%s</td><td>%s</td></tr>\n' \
        "$(html_escape "${id}")" "$(html_escape "${account_id}")" "$(html_escape "${kind}")" "$(html_escape "${amount}")" "$(html_escape "${timestamp}")"
    done <<< "${latest_transactions}"
  else
    echo '        <tr><td colspan="5">No transactions found.</td></tr>'
  fi

  cat <<'EOF'
      </tbody></table></div>
    </section>
  </main>
  <footer><div class="container">Generated automatically by the Banking Database Pipeline.</div></footer>
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
