#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-banking.sqlite}"
REPORT_PATH="${2:-reports/db-failure-report.html}"
REBUILD_LOG="${3:-reports/rebuild.log}"
VERIFY_LOG="${4:-reports/verify.log}"
FAILURE_REPORT="${5:-reports/db-verification-failures.tsv}"

generated_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
generated_local="$(date +"%B %d, %Y at %H:%M %Z")"

pipeline_workflow="${GITHUB_WORKFLOW:-Database Pipeline}"
pipeline_run_id="${GITHUB_RUN_ID:-local}"
pipeline_run_url=""
if [[ -n "${pipeline_run_id}" && -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  pipeline_run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${pipeline_run_id}"
fi

rebuild_outcome="${REBUILD_OUTCOME:-unknown}"
verify_outcome="${VERIFY_OUTCOME:-unknown}"

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

read_log_excerpt() {
  local log_file="$1"
  local max_lines="${2:-40}"

  if [[ ! -f "${log_file}" ]]; then
    printf '%s' "No log captured for this step."
    return
  fi

  tail -n "${max_lines}" "${log_file}" | while IFS= read -r line; do
    html_escape "${line}"
    printf '\n'
  done
}

failure_rows=""
if [[ -f "${FAILURE_REPORT}" ]]; then
  while IFS=$'\t' read -r check table_name query message; do
    [[ "${check}" == "check" ]] && continue
    [[ -z "${check}" ]] && continue
    failure_rows="${failure_rows}        <tr><td><code>$(html_escape "${check}")</code></td><td><code>$(html_escape "${table_name}")</code></td><td><pre class=\"query\">$(html_escape "${query}")</pre></td><td>$(html_escape "${message}")</td></tr>\n"
  done < "${FAILURE_REPORT}"
fi

if [[ -z "${failure_rows}" ]]; then
  if [[ "${rebuild_outcome}" == "failure" ]]; then
    failure_rows='        <tr><td><code>database_rebuild</code></td><td>-</td><td><pre class="query">make db-rebuild</pre></td><td>Database rebuild failed. Review the rebuild log excerpt below.</td></tr>'
  elif [[ "${verify_outcome}" == "failure" ]]; then
    failure_rows='        <tr><td><code>database_verify</code></td><td>-</td><td><pre class="query">make db-verify</pre></td><td>Database verification failed. Review the verification log excerpt below.</td></tr>'
  else
    failure_rows='        <tr><td colspan="4">No structured failure details were captured.</td></tr>'
  fi
fi

schema_rows=""
table_status_rows=""
if [[ -f "${DB_PATH}" ]] && command -v sqlite3 >/dev/null 2>&1; then
  schema_tables="$(sqlite3 -noheader "${DB_PATH}" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;" 2>/dev/null || true)"
  while IFS= read -r table_name; do
    [[ -z "${table_name}" ]] && continue
    row_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM \"${table_name}\";" 2>/dev/null || echo "n/a")"
    schema_rows="${schema_rows}        <tr><td><code>$(html_escape "${table_name}")</code></td><td class=\"numeric\">$(html_escape "${row_count}")</td></tr>\n"
    table_status_rows="${table_status_rows}        <tr><td><code>$(html_escape "${table_name}")</code></td><td class=\"numeric\">$(html_escape "${row_count}")</td><td>Present</td></tr>\n"
  done <<< "${schema_tables}"
fi

if [[ -z "${schema_rows}" ]]; then
  schema_rows='        <tr><td colspan="2">Database file unavailable or unreadable.</td></tr>'
  table_status_rows='        <tr><td colspan="3">Database file unavailable or unreadable.</td></tr>'
fi

rebuild_log_excerpt="$(read_log_excerpt "${REBUILD_LOG}")"
verify_log_excerpt="$(read_log_excerpt "${VERIFY_LOG}")"

mkdir -p "$(dirname "${REPORT_PATH}")"

cat > "${REPORT_PATH}" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Database Pipeline Failure Report</title>
  <style>
    :root {
      --ink: #111827;
      --muted: #6b7280;
      --line: #e5e7eb;
      --surface: #ffffff;
      --canvas: #fff7ed;
      --red: #b91c1c;
      --red-soft: #fef2f2;
      --amber: #b45309;
      --amber-soft: #fffbeb;
      --navy: #0f172a;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: linear-gradient(180deg, #fff7ed 0%, #ffffff 220px);
      color: var(--ink);
      font-family: "Segoe UI", ui-sans-serif, system-ui, sans-serif;
      line-height: 1.55;
    }
    .container { width: min(1080px, calc(100% - 32px)); margin: 0 auto; }
    header {
      padding: 42px 0 56px;
      color: #fff;
      background: linear-gradient(135deg, #7f1d1d 0%, #dc2626 55%, #f97316 100%);
    }
    .eyebrow {
      margin: 0 0 8px;
      font-size: .78rem;
      font-weight: 700;
      letter-spacing: .12em;
      text-transform: uppercase;
      color: #fecaca;
    }
    h1 { margin: 0; font-size: clamp(2rem, 4vw, 2.8rem); }
    .subtitle { margin: 14px 0 0; max-width: 720px; color: #fee2e2; }
    .meta { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 22px; }
    .chip {
      display: inline-flex;
      padding: 8px 12px;
      border-radius: 999px;
      background: rgba(255,255,255,.14);
      color: #fff7ed;
      font-size: .86rem;
    }
    main { padding: 0 0 48px; }
    .panel {
      margin-top: -28px;
      padding: 22px 24px;
      border: 1px solid var(--line);
      border-radius: 16px;
      background: var(--surface);
      box-shadow: 0 16px 40px rgba(15, 23, 42, .08);
    }
    section { margin-top: 28px; }
    h2 { margin: 0 0 14px; font-size: 1.15rem; }
    .table-wrap { overflow-x: auto; border: 1px solid var(--line); border-radius: 12px; background: var(--surface); }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 14px 16px; border-bottom: 1px solid var(--line); vertical-align: top; text-align: left; }
    th {
      background: #f9fafb;
      color: var(--muted);
      font-size: .74rem;
      letter-spacing: .08em;
      text-transform: uppercase;
    }
    tr:last-child td { border-bottom: 0; }
    .numeric { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
    pre.query, pre.log {
      margin: 0;
      padding: 10px 12px;
      border-radius: 8px;
      background: #111827;
      color: #f9fafb;
      font-size: .82rem;
      line-height: 1.45;
      white-space: pre-wrap;
      word-break: break-word;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      border-radius: 999px;
      background: var(--red-soft);
      color: var(--red);
      font-size: .82rem;
      font-weight: 800;
      text-transform: uppercase;
    }
    .link { color: #2563eb; text-decoration: none; font-weight: 600; }
    footer { padding: 24px 0 36px; color: var(--muted); font-size: .88rem; border-top: 1px solid var(--line); }
  </style>
</head>
<body>
  <header>
    <div class="container">
      <p class="eyebrow">Banking database pipeline alert</p>
      <h1>Pipeline Failure Report</h1>
      <p class="subtitle">The database pipeline did not complete successfully. Review the failed checks, affected tables, queries, and captured logs below.</p>
      <div class="meta">
        <span class="chip">Generated $(html_escape "${generated_utc}")</span>
        <span class="chip">Workflow $(html_escape "${pipeline_workflow}")</span>
        <span class="chip">Run #$(html_escape "${pipeline_run_id}")</span>
      </div>
    </div>
  </header>

  <main class="container">
    <div class="panel">
      <span class="badge">Execution failed</span>
      <p style="margin:14px 0 0;color:var(--muted);">Report prepared on $(html_escape "${generated_local}") for database <code>$(html_escape "${DB_PATH}")</code>.</p>
      $(if [[ -n "${pipeline_run_url}" ]]; then echo "<p style=\"margin-top:10px;\"><a class=\"link\" href=\"$(html_escape "${pipeline_run_url}")\">Open workflow run</a></p>"; fi)
    </div>

    <section>
      <h2>Step Outcomes</h2>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Step</th><th>Outcome</th><th>Notes</th></tr></thead>
          <tbody>
            <tr><td>Rebuild database</td><td>$(html_escape "${rebuild_outcome}")</td><td>Runs migrations and seed data via <code>make db-rebuild</code></td></tr>
            <tr><td>Verify database</td><td>$(html_escape "${verify_outcome}")</td><td>Validates required tables, seed minimums, and referential integrity</td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <section>
      <h2>Failure Details</h2>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Check</th><th>Table</th><th>Query</th><th>Error</th></tr></thead>
          <tbody>
$(printf '%b' "${failure_rows}")
          </tbody>
        </table>
      </div>
    </section>

    <section>
      <h2>Current Table Status</h2>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Table</th><th class="numeric">Rows</th><th>Status</th></tr></thead>
          <tbody>
$(printf '%b' "${table_status_rows}")
          </tbody>
        </table>
      </div>
    </section>

    <section>
      <h2>Rebuild Log Excerpt</h2>
      <pre class="log">${rebuild_log_excerpt}</pre>
    </section>

    <section>
      <h2>Verification Log Excerpt</h2>
      <pre class="log">${verify_log_excerpt}</pre>
    </section>
  </main>

  <footer>
    <div class="container">Generated automatically by the Banking Database Pipeline.</div>
  </footer>
</body>
</html>
EOF

echo "Failure report generated at ${REPORT_PATH}"
