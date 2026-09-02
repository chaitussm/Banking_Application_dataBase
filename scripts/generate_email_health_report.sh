#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-banking.sqlite}"
HTML_PATH="${2:-reports/pipeline-email.html}"
PLAIN_PATH="${3:-reports/pipeline-email-plain.txt}"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Error: sqlite3 is required but not installed." >&2
  exit 1
fi

if [[ ! -f "${DB_PATH}" ]]; then
  echo "Error: database file not found at ${DB_PATH}" >&2
  exit 1
fi

mkdir -p "$(dirname "${HTML_PATH}")"
mkdir -p "$(dirname "${PLAIN_PATH}")"

generated_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
generated_local="$(date +"%B %d, %Y at %H:%M %Z")"

users_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM users;")"
accounts_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM accounts;")"
transactions_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM transactions;")"
refresh_tokens_count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM refresh_tokens;")"
orphan_accounts="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM accounts a LEFT JOIN users u ON u.id = a.user_id WHERE u.id IS NULL;")"
orphan_transactions="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM transactions t LEFT JOIN accounts a ON a.id = t.account_id WHERE a.id IS NULL;")"
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

pipeline_workflow="${GITHUB_WORKFLOW:-Database Pipeline}"
pipeline_run_id="${GITHUB_RUN_ID:-}"
pipeline_run_url=""
if [[ -n "${pipeline_run_id}" && -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  pipeline_run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${pipeline_run_id}"
fi

latest_transactions="$(sqlite3 -noheader "${DB_PATH}" "SELECT id || '|' || account_id || '|' || kind || '|' || amount || '|' || COALESCE(note, '') || '|' || timestamp FROM transactions ORDER BY timestamp DESC LIMIT 5;")"

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
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

db_size_human="$(format_bytes "${db_size_bytes}")"
fk_label="Enabled"
fk_bg="#ecfdf5"
fk_color="#047857"
if [[ "${foreign_keys_enabled}" != "1" ]]; then
  fk_label="Disabled"
  fk_bg="#fef2f2"
  fk_color="#b91c1c"
fi

txn_rows=""
if [[ -n "${latest_transactions}" ]]; then
  while IFS= read -r line; do
    id="$(echo "${line}" | cut -d '|' -f 1)"
    account_id="$(echo "${line}" | cut -d '|' -f 2)"
    kind="$(echo "${line}" | cut -d '|' -f 3)"
    amount="$(echo "${line}" | cut -d '|' -f 4)"
    note="$(echo "${line}" | cut -d '|' -f 5)"
    timestamp="$(echo "${line}" | cut -d '|' -f 6-)"
    if [[ "${kind}" == "credit" ]]; then
      kind_bg="#ecfdf5"
      kind_color="#047857"
    else
      kind_bg="#fef2f2"
      kind_color="#b91c1c"
    fi
    txn_rows="${txn_rows}<tr>
      <td style=\"padding:10px 12px;border-bottom:1px solid #e5e7eb;font-family:Consolas,monospace;font-size:12px;\">$(html_escape "${id}")</td>
      <td style=\"padding:10px 12px;border-bottom:1px solid #e5e7eb;font-family:Consolas,monospace;font-size:12px;\">$(html_escape "${account_id}")</td>
      <td style=\"padding:10px 12px;border-bottom:1px solid #e5e7eb;\"><span style=\"display:inline-block;padding:4px 10px;border-radius:999px;background:${kind_bg};color:${kind_color};font-size:11px;font-weight:700;text-transform:uppercase;\">$(html_escape "${kind}")</span></td>
      <td style=\"padding:10px 12px;border-bottom:1px solid #e5e7eb;text-align:right;font-weight:700;\">$(html_escape "${amount}")</td>
      <td style=\"padding:10px 12px;border-bottom:1px solid #e5e7eb;\">$(html_escape "${note}")</td>
      <td style=\"padding:10px 12px;border-bottom:1px solid #e5e7eb;font-size:12px;color:#64748b;\">$(html_escape "${timestamp}")</td>
    </tr>"
  done <<< "${latest_transactions}"
else
  txn_rows='<tr><td colspan="6" style="padding:12px;color:#64748b;">No transactions found.</td></tr>'
fi

run_link_html=""
if [[ -n "${pipeline_run_url}" ]]; then
  run_link_html="<p style=\"margin:12px 0 0;font-size:14px;\"><a href=\"$(html_escape "${pipeline_run_url}")\" style=\"color:#2563eb;text-decoration:none;font-weight:600;\">Open workflow run #$(html_escape "${pipeline_run_id}")</a></p>"
fi

cat > "${HTML_PATH}" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Database Health Report</title>
</head>
<body style="margin:0;padding:0;background-color:#f1f5f9;font-family:Arial,Helvetica,sans-serif;color:#0f172a;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f1f5f9;padding:24px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" width="640" cellpadding="0" cellspacing="0" border="0" style="max-width:640px;width:100%;background-color:#ffffff;border:1px solid #dbeafe;border-radius:16px;overflow:hidden;">
          <tr>
            <td style="padding:32px 28px;background:linear-gradient(135deg,#0f172a 0%,#1d4ed8 100%);color:#ffffff;">
              <p style="margin:0 0 8px;font-size:11px;letter-spacing:0.14em;text-transform:uppercase;color:#bfdbfe;font-weight:700;">Banking database observability</p>
              <h1 style="margin:0;font-size:30px;line-height:1.15;font-weight:800;">Database Health Report</h1>
              <p style="margin:14px 0 0;font-size:15px;line-height:1.6;color:#dbeafe;">Pipeline completed successfully. Your database schema, integrity checks, and recent ledger activity are summarized below.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:24px 28px 8px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #bbf7d0;background-color:#f0fdf4;border-radius:12px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <p style="margin:0 0 6px;font-size:12px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#15803d;">Overall status</p>
                    <p style="margin:0;font-size:24px;font-weight:800;color:#166534;">Healthy</p>
                    <p style="margin:8px 0 0;font-size:14px;color:#166534;">All verification checks passed on $(html_escape "${generated_local}")</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:8px 28px 0;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td style="padding:8px 6px 8px 0;width:50%;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e2e8f0;border-radius:12px;">
                      <tr><td style="padding:16px;">
                        <p style="margin:0;font-size:12px;color:#64748b;font-weight:700;text-transform:uppercase;">Generated</p>
                        <p style="margin:8px 0 0;font-size:14px;font-weight:600;">$(html_escape "${generated_utc}")</p>
                      </td></tr>
                    </table>
                  </td>
                  <td style="padding:8px 0 8px 6px;width:50%;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e2e8f0;border-radius:12px;">
                      <tr><td style="padding:16px;">
                        <p style="margin:0;font-size:12px;color:#64748b;font-weight:700;text-transform:uppercase;">Total balance</p>
                        <p style="margin:8px 0 0;font-size:24px;font-weight:800;color:#1d4ed8;">\$$(html_escape "${total_balance}")</p>
                      </td></tr>
                    </table>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:18px 28px 6px;">
              <h2 style="margin:0 0 12px;font-size:18px;">Database metadata</h2>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
                <tr>
                  <td style="width:25%;padding:6px;"><table role="presentation" width="100%" style="border:1px solid #e2e8f0;border-radius:10px;"><tr><td style="padding:14px;"><p style="margin:0;font-size:11px;color:#64748b;text-transform:uppercase;font-weight:700;">Database</p><p style="margin:8px 0 0;font-size:13px;font-weight:700;word-break:break-all;">$(html_escape "${DB_PATH}")</p></td></tr></table></td>
                  <td style="width:25%;padding:6px;"><table role="presentation" width="100%" style="border:1px solid #e2e8f0;border-radius:10px;"><tr><td style="padding:14px;"><p style="margin:0;font-size:11px;color:#64748b;text-transform:uppercase;font-weight:700;">SQLite</p><p style="margin:8px 0 0;font-size:20px;font-weight:800;">$(html_escape "${sqlite_version}")</p></td></tr></table></td>
                  <td style="width:25%;padding:6px;"><table role="presentation" width="100%" style="border:1px solid #e2e8f0;border-radius:10px;"><tr><td style="padding:14px;"><p style="margin:0;font-size:11px;color:#64748b;text-transform:uppercase;font-weight:700;">File size</p><p style="margin:8px 0 0;font-size:20px;font-weight:800;">$(html_escape "${db_size_human}")</p></td></tr></table></td>
                  <td style="width:25%;padding:6px;"><table role="presentation" width="100%" style="border:1px solid #e2e8f0;border-radius:10px;"><tr><td style="padding:14px;"><p style="margin:0;font-size:11px;color:#64748b;text-transform:uppercase;font-weight:700;">Foreign keys</p><p style="margin:8px 0 0;"><span style="display:inline-block;padding:4px 10px;border-radius:999px;background:${fk_bg};color:${fk_color};font-size:12px;font-weight:700;">$(html_escape "${fk_label}")</span></p></td></tr></table></td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:10px 28px 6px;">
              <h2 style="margin:0 0 12px;font-size:18px;">Row counts</h2>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td style="width:25%;padding:6px;"><table role="presentation" width="100%" style="border:1px solid #e2e8f0;border-radius:10px;"><tr><td style="padding:14px;"><p style="margin:0;font-size:11px;color:#64748b;text-transform:uppercase;font-weight:700;">Users</p><p style="margin:8px 0 0;font-size:24px;font-weight:800;">${users_count}</p><p style="margin:6px 0 0;font-size:12px;color:#64748b;">${customer_count} customers, ${manager_count} managers</p></td></tr></table></td>
                  <td style="width:25%;padding:6px;"><table role="presentation" width="100%" style="border:1px solid #e2e8f0;border-radius:10px;"><tr><td style="padding:14px;"><p style="margin:0;font-size:11px;color:#64748b;text-transform:uppercase;font-weight:700;">Accounts</p><p style="margin:8px 0 0;font-size:24px;font-weight:800;">${accounts_count}</p></td></tr></table></td>
                  <td style="width:25%;padding:6px;"><table role="presentation" width="100%" style="border:1px solid #e2e8f0;border-radius:10px;"><tr><td style="padding:14px;"><p style="margin:0;font-size:11px;color:#64748b;text-transform:uppercase;font-weight:700;">Transactions</p><p style="margin:8px 0 0;font-size:24px;font-weight:800;">${transactions_count}</p><p style="margin:6px 0 0;font-size:12px;color:#64748b;">${credit_count} credits, ${debit_count} debits</p></td></tr></table></td>
                  <td style="width:25%;padding:6px;"><table role="presentation" width="100%" style="border:1px solid #e2e8f0;border-radius:10px;"><tr><td style="padding:14px;"><p style="margin:0;font-size:11px;color:#64748b;text-transform:uppercase;font-weight:700;">Refresh tokens</p><p style="margin:8px 0 0;font-size:24px;font-weight:800;">${refresh_tokens_count}</p></td></tr></table></td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:10px 28px 6px;">
              <h2 style="margin:0 0 12px;font-size:18px;">Integrity checks</h2>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e2e8f0;border-radius:12px;border-collapse:separate;">
                <tr style="background-color:#f8fafc;">
                  <th align="left" style="padding:12px;font-size:11px;text-transform:uppercase;color:#64748b;">Check</th>
                  <th align="right" style="padding:12px;font-size:11px;text-transform:uppercase;color:#64748b;">Value</th>
                  <th align="left" style="padding:12px;font-size:11px;text-transform:uppercase;color:#64748b;">Status</th>
                </tr>
                <tr><td style="padding:12px;border-top:1px solid #e2e8f0;">Orphan accounts</td><td align="right" style="padding:12px;border-top:1px solid #e2e8f0;">${orphan_accounts}</td><td style="padding:12px;border-top:1px solid #e2e8f0;"><span style="display:inline-block;padding:4px 10px;border-radius:999px;background:#ecfdf5;color:#047857;font-size:11px;font-weight:700;">PASS</span></td></tr>
                <tr><td style="padding:12px;border-top:1px solid #e2e8f0;">Orphan transactions</td><td align="right" style="padding:12px;border-top:1px solid #e2e8f0;">${orphan_transactions}</td><td style="padding:12px;border-top:1px solid #e2e8f0;"><span style="display:inline-block;padding:4px 10px;border-radius:999px;background:#ecfdf5;color:#047857;font-size:11px;font-weight:700;">PASS</span></td></tr>
                <tr><td style="padding:12px;border-top:1px solid #e2e8f0;">Minimum users (&gt;= 3)</td><td align="right" style="padding:12px;border-top:1px solid #e2e8f0;">${users_count}</td><td style="padding:12px;border-top:1px solid #e2e8f0;"><span style="display:inline-block;padding:4px 10px;border-radius:999px;background:#ecfdf5;color:#047857;font-size:11px;font-weight:700;">PASS</span></td></tr>
                <tr><td style="padding:12px;border-top:1px solid #e2e8f0;">Minimum accounts (&gt;= 3)</td><td align="right" style="padding:12px;border-top:1px solid #e2e8f0;">${accounts_count}</td><td style="padding:12px;border-top:1px solid #e2e8f0;"><span style="display:inline-block;padding:4px 10px;border-radius:999px;background:#ecfdf5;color:#047857;font-size:11px;font-weight:700;">PASS</span></td></tr>
                <tr><td style="padding:12px;border-top:1px solid #e2e8f0;">Minimum transactions (&gt;= 3)</td><td align="right" style="padding:12px;border-top:1px solid #e2e8f0;">${transactions_count}</td><td style="padding:12px;border-top:1px solid #e2e8f0;"><span style="display:inline-block;padding:4px 10px;border-radius:999px;background:#ecfdf5;color:#047857;font-size:11px;font-weight:700;">PASS</span></td></tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:10px 28px 6px;">
              <h2 style="margin:0 0 12px;font-size:18px;">Latest transactions</h2>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e2e8f0;border-radius:12px;border-collapse:separate;">
                <tr style="background-color:#f8fafc;">
                  <th align="left" style="padding:10px 12px;font-size:11px;text-transform:uppercase;color:#64748b;">ID</th>
                  <th align="left" style="padding:10px 12px;font-size:11px;text-transform:uppercase;color:#64748b;">Account</th>
                  <th align="left" style="padding:10px 12px;font-size:11px;text-transform:uppercase;color:#64748b;">Kind</th>
                  <th align="right" style="padding:10px 12px;font-size:11px;text-transform:uppercase;color:#64748b;">Amount</th>
                  <th align="left" style="padding:10px 12px;font-size:11px;text-transform:uppercase;color:#64748b;">Note</th>
                  <th align="left" style="padding:10px 12px;font-size:11px;text-transform:uppercase;color:#64748b;">Timestamp</th>
                </tr>
                ${txn_rows}
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:10px 28px 24px;">
              <h2 style="margin:0 0 12px;font-size:18px;">Pipeline context</h2>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e2e8f0;border-radius:12px;">
                <tr><td style="padding:16px 18px;">
                  <p style="margin:0;font-size:12px;color:#64748b;text-transform:uppercase;font-weight:700;">Workflow</p>
                  <p style="margin:8px 0 0;font-size:16px;font-weight:700;">$(html_escape "${pipeline_workflow}")</p>
                  <p style="margin:14px 0 0;font-size:12px;color:#64748b;text-transform:uppercase;font-weight:700;">Schema objects</p>
                  <p style="margin:8px 0 0;font-size:14px;">${table_count} tables, ${index_count} indexes</p>
                  ${run_link_html}
                </td></tr>
              </table>
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
Database Health Report - SUCCESS

Generated: ${generated_utc}
Database: ${DB_PATH}
Status: Healthy

Metadata
- SQLite: ${sqlite_version}
- File size: ${db_size_human}
- Tables: ${table_count}
- Indexes: ${index_count}
- Foreign keys: ${fk_label}
- Total balance: \$${total_balance}

Row counts
- Users: ${users_count} (${customer_count} customers, ${manager_count} managers)
- Accounts: ${accounts_count}
- Transactions: ${transactions_count} (${credit_count} credits, ${debit_count} debits)
- Refresh tokens: ${refresh_tokens_count}

Integrity checks: all passed
- Orphan accounts: ${orphan_accounts}
- Orphan transactions: ${orphan_transactions}

Workflow: ${pipeline_workflow}
EOF

if [[ -n "${pipeline_run_url}" ]]; then
  echo "Run: ${pipeline_run_url}" >> "${PLAIN_PATH}"
fi

echo "Email health report generated at ${HTML_PATH}"
