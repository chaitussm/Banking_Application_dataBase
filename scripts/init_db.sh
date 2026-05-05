#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-banking.sqlite}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v sqlite3 >/dev/null 2>&1; then
	echo "Error: sqlite3 is required but not installed." >&2
	exit 1
fi

mkdir -p "$(dirname "${DB_PATH}")"

sqlite3 "${DB_PATH}" < "${ROOT_DIR}/db/migrations/001_init_banking_schema.sql"
sqlite3 "${DB_PATH}" < "${ROOT_DIR}/db/migrations/002_seed_initial_data.sql"

echo "Database initialized at ${DB_PATH}"
