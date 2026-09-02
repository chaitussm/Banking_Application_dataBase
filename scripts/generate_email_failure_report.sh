#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-banking.sqlite}"
HTML_PATH="${2:-reports/pipeline-email.html}"
PLAIN_PATH="${3:-reports/pipeline-email-plain.txt}"
REBUILD_LOG="${4:-reports/rebuild.log}"
VERIFY_LOG="${5:-reports/verify.log}"
FAILURE_REPORT="${6:-reports/db-verification-failures.tsv}"

generated_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
generated_local="$(date +"%B %d, %Y at %H:%M %Z")"
rebuild_outcome="${REBUILD_OUTCOME:-unknown}"
verify_outcome="${VERIFY_OUTCOME:-unknown}"
pipeline_workflow="${GITHUB_WORKFLOW:-Database Pipeline}"
pipeline_run_id="${GITHUB_RUN_ID:-}"
pipeline_run_url=""
if [[ -n "${pipeline_run_id}" && -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  pipeline_run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${pipeline_run_id}"
fi

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

read_log_excerpt() {
  local log_file="$1"
  local max_lines="${2:-20}"
  if [[ ! -f "${log_file}" ]]; then
    echo "No log captured for this step."
    return
  fi
  tail -n "${max_lines}" "${log_file}" | while IFS= read -r line; do
    html_escape "${line}"
    printf '\n'
  done
}

failure_rows=""
plain_failures=""
if [[ -f "${FAILURE_REPORT}" ]]; then
  while IFS=$'\t' read -r check table_name query message; do
    [[ "${check}" == "check" ]] && continue
    [[ -z "${check}" ]] && continue
    failure_rows="${failure_rows}<tr>
      <td style=\"padding:12px;border-top:1px solid #fecaca;font-family:Consolas,monospace;font-size:12px;\">$(html_escape "${check}")</td>
      <td style=\"padding:12px;border-top:1px solid #fecaca;font-family:Consolas,monospace;font-size:12px;\">$(html_escape "${table_name}")</td>
      <td style=\"padding:12px;border-top:1px solid #fecaca;font-family:Consolas,monospace;font-size:11px;word-break:break-word;\">$(html_escape "${query}")</td>
      <td style=\"padding:12px;border-top:1px solid #fecaca;\">$(html_escape "${message}")</td>
    </tr>"
    plain_failures="${plain_failures}
- ${check} | table=${table_name} | ${message}
  query: ${query}"
  done < "${FAILURE_REPORT}"
fi

if [[ -z "${failure_rows}" ]]; then
  if [[ "${rebuild_outcome}" == "failure" ]]; then
    failure_rows='<tr><td style="padding:12px;border-top:1px solid #fecaca;">database_rebuild</td><td style="padding:12px;border-top:1px solid #fecaca;">-</td><td style="padding:12px;border-top:1px solid #fecaca;">make db-rebuild</td><td style="padding:12px;border-top:1px solid #fecaca;">Database rebuild failed. Review rebuild log below.</td></tr>'
    plain_failures="- database_rebuild failed during make db-rebuild"
  else
    failure_rows='<tr><td colspan="4" style="padding:12px;">Database verification failed. Review verification log below.</td></tr>'
    plain_failures="- database_verify failed during make db-verify"
  fi
fi

table_rows=""
plain_tables=""
if [[ -f "${DB_PATH}" ]] && command -v sqlite3 >/dev/null 2>&1; then
  schema_tables="$(sqlite3 -noheader "${DB_PATH}" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;" 2>/dev/null || true)"
  while IFS= read -r table_name; do
    [[ -z "${table_name}" ]] && continue
    row_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM \"${table_name}\";" 2>/dev/null || echo "n/a")"
    table_rows="${table_rows}<tr><td style=\"padding:12px;border-top:1px solid #e2e8f0;font-family:Consolas,monospace;\">$(html_escape "${table_name}")</td><td align=\"right\" style=\"padding:12px;border-top:1px solid #e2e8f0;\">$(html_escape "${row_count}")</td><td style=\"padding:12px;border-top:1px solid #e2e8f0;\">Present</td></tr>"
    plain_tables="${plain_tables}
- ${table_name}: ${row_count} rows"
  done <<< "${schema_tables}"
fi

if [[ -z "${table_rows}" ]]; then
  table_rows='<tr><td colspan="3" style="padding:12px;">Database file unavailable or unreadable.</td></tr>'
  plain_tables="- Database unavailable"
fi

rebuild_log_excerpt="$(read_log_excerpt "${REBUILD_LOG}")"
verify_log_excerpt="$(read_log_excerpt "${VERIFY_LOG}")"
run_link_html=""
if [[ -n "${pipeline_run_url}" ]]; then
  run_link_html="<p style=\"margin:12px 0 0;font-size:14px;\"><a href=\"$(html_escape "${pipeline_run_url}")\" style=\"color:#2563eb;text-decoration:none;font-weight:600;\">Open workflow run #$(html_escape "${pipeline_run_id}")</a></p>"
fi

mkdir -p "$(dirname "${HTML_PATH}")"
mkdir -p "$(dirname "${PLAIN_PATH}")"

cat > "${HTML_PATH}" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Database Pipeline Failure Report</title>
</head>
<body style="margin:0;padding:0;background-color:#fff7ed;font-family:Arial,Helvetica,sans-serif;color:#111827;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#fff7ed;padding:24px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" width="640" cellpadding="0" cellspacing="0" border="0" style="max-width:640px;width:100%;background-color:#ffffff;border:1px solid #fecaca;border-radius:16px;overflow:hidden;">
          <tr>
            <td style="padding:32px 28px;background:linear-gradient(135deg,#7f1d1d 0%,#dc2626 100%);color:#ffffff;">
              <p style="margin:0 0 8px;font-size:11px;letter-spacing:0.14em;text-transform:uppercase;color:#fecaca;font-weight:700;">Pipeline alert</p>
              <h1 style="margin:0;font-size:30px;line-height:1.15;font-weight:800;">Database Pipeline Failed</h1>
              <p style="margin:14px 0 0;font-size:15px;line-height:1.6;color:#fee2e2;">The pipeline did not complete successfully. Review the failed check, affected table, SQL query, and error details below.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:24px 28px 8px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #fecaca;background-color:#fef2f2;border-radius:12px;">
                <tr><td style="padding:18px 20px;">
                  <p style="margin:0 0 6px;font-size:12px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#b91c1c;">Execution status</p>
                  <p style="margin:0;font-size:24px;font-weight:800;color:#991b1b;">Action required</p>
                  <p style="margin:8px 0 0;font-size:14px;color:#991b1b;">Report generated on $(html_escape "${generated_local}")</p>
                </td></tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:8px 28px 6px;">
              <h2 style="margin:0 0 12px;font-size:18px;">Step outcomes</h2>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e2e8f0;border-radius:12px;">
                <tr style="background-color:#f8fafc;"><th align="left" style="padding:12px;font-size:11px;text-transform:uppercase;color:#64748b;">Step</th><th align="left" style="padding:12px;font-size:11px;text-transform:uppercase;color:#64748b;">Outcome</th></tr>
                <tr><td style="padding:12px;border-top:1px solid #e2e8f0;">Rebuild database</td><td style="padding:12px;border-top:1px solid #e2e8f0;font-weight:700;">$(html_escape "${rebuild_outcome}")</td></tr>
                <tr><td style="padding:12px;border-top:1px solid #e2e8f0;">Verify database</td><td style="padding:12px;border-top:1px solid #e2e8f0;font-weight:700;">$(html_escape "${verify_outcome}")</td></tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:10px 28px 6px;">
              <h2 style="margin:0 0 12px;font-size:18px;">Failure details</h2>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #fecaca;border-radius:12px;">
                <tr style="background-color:#fef2f2;">
                  <th align="left" style="padding:12px;font-size:11px;text-transform:uppercase;color:#991b1b;">Check</th>
                  <th align="left" style="padding:12px;font-size:11px;text-transform:uppercase;color:#991b1b;">Table</th>
                  <th align="left" style="padding:12px;font-size:11px;text-transform:uppercase;color:#991b1b;">Query</th>
                  <th align="left" style="padding:12px;font-size:11px;text-transform:uppercase;color:#991b1b;">Error</th>
                </tr>
                ${failure_rows}
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:10px 28px 6px;">
              <h2 style="margin:0 0 12px;font-size:18px;">Current table status</h2>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e2e8f0;border-radius:12px;">
                <tr style="background-color:#f8fafc;"><th align="left" style="padding:12px;font-size:11px;text-transform:uppercase;color:#64748b;">Table</th><th align="right" style="padding:12px;font-size:11px;text-transform:uppercase;color:#64748b;">Rows</th><th align="left" style="padding:12px;font-size:11px;text-transform:uppercase;color:#64748b;">Status</th></tr>
                ${table_rows}
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:10px 28px 6px;">
              <h2 style="margin:0 0 12px;font-size:18px;">Rebuild log excerpt</h2>
              <pre style="margin:0;padding:14px;background-color:#111827;color:#f9fafb;border-radius:10px;font-size:12px;line-height:1.5;white-space:pre-wrap;word-break:break-word;">${rebuild_log_excerpt}</pre>
            </td>
          </tr>
          <tr>
            <td style="padding:10px 28px 18px;">
              <h2 style="margin:0 0 12px;font-size:18px;">Verification log excerpt</h2>
              <pre style="margin:0;padding:14px;background-color:#111827;color:#f9fafb;border-radius:10px;font-size:12px;line-height:1.5;white-space:pre-wrap;word-break:break-word;">${verify_log_excerpt}</pre>
              ${run_link_html}
            </td>
          </tr>
          <tr>
            <td style="padding:18px 28px;background-color:#f8fafc;border-top:1px solid #e2e8f0;color:#64748b;font-size:12px;">
              Generated automatically by the Banking Database Pipeline.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
EOF

cat > "${PLAIN_PATH}" <<EOF
Database Pipeline Failure Report

Generated: ${generated_utc}
Database: ${DB_PATH}
Workflow: ${pipeline_workflow}

Step outcomes
- Rebuild: ${rebuild_outcome}
- Verify: ${verify_outcome}

Failure details${plain_failures}

Current tables${plain_tables}

Rebuild log excerpt:
$(tail -n 20 "${REBUILD_LOG}" 2>/dev/null || echo "No rebuild log")

Verification log excerpt:
$(tail -n 20 "${VERIFY_LOG}" 2>/dev/null || echo "No verification log")
EOF

if [[ -n "${pipeline_run_url}" ]]; then
  echo "Run: ${pipeline_run_url}" >> "${PLAIN_PATH}"
fi

echo "Email failure report generated at ${HTML_PATH}"
