#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-banking.sqlite}"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Error: sqlite3 is required but not installed." >&2
  exit 1
fi

if [[ ! -f "${DB_PATH}" ]]; then
  echo "Error: database file not found at ${DB_PATH}" >&2
  echo "Run: make db-init DB_FILE=${DB_PATH}" >&2
  exit 1
fi

required_tables=(users accounts transactions refresh_tokens)
for table in "${required_tables[@]}"; do
  exists=$(sqlite3 "${DB_PATH}" "SELECT COUNT(1) FROM sqlite_master WHERE type='table' AND name='${table}';")
  if [[ "${exists}" != "1" ]]; then
    echo "Error: required table missing: ${table}" >&2
    exit 1
  fi
done

users_count=$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM users;")
accounts_count=$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM accounts;")
transactions_count=$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM transactions;")

if [[ "${users_count}" -lt 3 ]]; then
  echo "Error: expected at least 3 users, found ${users_count}" >&2
  exit 1
fi

if [[ "${accounts_count}" -lt 3 ]]; then
  echo "Error: expected at least 3 accounts, found ${accounts_count}" >&2
  exit 1
fi

if [[ "${transactions_count}" -lt 3 ]]; then
  echo "Error: expected at least 3 transactions, found ${transactions_count}" >&2
  exit 1
fi

orphan_accounts=$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM accounts a LEFT JOIN users u ON u.id = a.user_id WHERE u.id IS NULL;")
orphan_transactions=$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM transactions t LEFT JOIN accounts a ON a.id = t.account_id WHERE a.id IS NULL;")

if [[ "${orphan_accounts}" != "0" ]]; then
  echo "Error: found ${orphan_accounts} account rows without matching users." >&2
  exit 1
fi

if [[ "${orphan_transactions}" != "0" ]]; then
  echo "Error: found ${orphan_transactions} transaction rows without matching accounts." >&2
  exit 1
fi

echo "Database verification passed for ${DB_PATH}"
echo "users=${users_count}, accounts=${accounts_count}, transactions=${transactions_count}"
