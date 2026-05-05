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

{
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
} > "${REPORT_PATH}"

echo "Report generated at ${REPORT_PATH}"
