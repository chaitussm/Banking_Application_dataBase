#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-banking.sqlite}"
FAILURE_REPORT_PATH="${VERIFY_FAILURE_REPORT:-reports/db-verification-failures.tsv}"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Error: sqlite3 is required but not installed." >&2
  exit 1
fi

failures=()

record_failure() {
  local check="$1"
  local table_name="$2"
  local query="$3"
  local message="$4"
  failures+=("${check}|${table_name}|${query}|${message}")
  echo "Error: ${message}" >&2
}

write_failure_report() {
  if [[ "${#failures[@]}" -eq 0 ]]; then
    return 0
  fi

  mkdir -p "$(dirname "${FAILURE_REPORT_PATH}")"
  {
    echo -e "check\ttable\tquery\tmessage"
    for failure in "${failures[@]}"; do
      IFS='|' read -r check table_name query message <<< "${failure}"
      printf '%s\t%s\t%s\t%s\n' "${check}" "${table_name}" "${query}" "${message}"
    done
  } > "${FAILURE_REPORT_PATH}"
}

if [[ ! -f "${DB_PATH}" ]]; then
  record_failure \
    "database_file" \
    "-" \
    "-" \
    "Database file not found at ${DB_PATH}. Run: make db-init DB_FILE=${DB_PATH}"
  write_failure_report
  exit 1
fi

required_tables=(users accounts transactions refresh_tokens)
for table in "${required_tables[@]}"; do
  table_query="SELECT COUNT(1) FROM sqlite_master WHERE type='table' AND name='${table}';"
  exists="$(sqlite3 "${DB_PATH}" "${table_query}")"
  if [[ "${exists}" != "1" ]]; then
    record_failure \
      "missing_table" \
      "${table}" \
      "${table_query}" \
      "Required table missing: ${table}"
  fi
done

if [[ "${#failures[@]}" -gt 0 ]]; then
  write_failure_report
  exit 1
fi

users_query="SELECT COUNT(*) FROM users;"
accounts_query="SELECT COUNT(*) FROM accounts;"
transactions_query="SELECT COUNT(*) FROM transactions;"

users_count="$(sqlite3 "${DB_PATH}" "${users_query}")"
accounts_count="$(sqlite3 "${DB_PATH}" "${accounts_query}")"
transactions_count="$(sqlite3 "${DB_PATH}" "${transactions_query}")"

if [[ "${users_count}" -lt 3 ]]; then
  record_failure \
    "seed_minimum" \
    "users" \
    "${users_query}" \
    "Expected at least 3 users, found ${users_count}"
fi

if [[ "${accounts_count}" -lt 3 ]]; then
  record_failure \
    "seed_minimum" \
    "accounts" \
    "${accounts_query}" \
    "Expected at least 3 accounts, found ${accounts_count}"
fi

if [[ "${transactions_count}" -lt 3 ]]; then
  record_failure \
    "seed_minimum" \
    "transactions" \
    "${transactions_query}" \
    "Expected at least 3 transactions, found ${transactions_count}"
fi

orphan_accounts_query="SELECT COUNT(*) FROM accounts a LEFT JOIN users u ON u.id = a.user_id WHERE u.id IS NULL;"
orphan_transactions_query="SELECT COUNT(*) FROM transactions t LEFT JOIN accounts a ON a.id = t.account_id WHERE a.id IS NULL;"

orphan_accounts="$(sqlite3 "${DB_PATH}" "${orphan_accounts_query}")"
orphan_transactions="$(sqlite3 "${DB_PATH}" "${orphan_transactions_query}")"

if [[ "${orphan_accounts}" != "0" ]]; then
  record_failure \
    "referential_integrity" \
    "accounts" \
    "${orphan_accounts_query}" \
    "Found ${orphan_accounts} account row(s) without matching users"
fi

if [[ "${orphan_transactions}" != "0" ]]; then
  record_failure \
    "referential_integrity" \
    "transactions" \
    "${orphan_transactions_query}" \
    "Found ${orphan_transactions} transaction row(s) without matching accounts"
fi

if [[ "${#failures[@]}" -gt 0 ]]; then
  write_failure_report
  exit 1
fi

rm -f "${FAILURE_REPORT_PATH}"

echo "Database verification passed for ${DB_PATH}"
echo "users=${users_count}, accounts=${accounts_count}, transactions=${transactions_count}"
