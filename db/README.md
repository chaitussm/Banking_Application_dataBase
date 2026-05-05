# Database Framework (Derived From Banking_Application)

This folder contains a migration-first database framework aligned with the upstream `Banking_Application` backend model.

## Database Engine

- SQLite
- Foreign keys enabled via `PRAGMA foreign_keys = ON`

## Entity Model

- `users`
  - Authentication identity and profile data
  - Includes lockout controls: `failed_login_attempts`, `locked_until`
- `accounts`
  - One user can own one or more bank accounts
  - Includes `type`, `balance`, and `currency`
- `transactions`
  - Credit/debit ledger entries tied to accounts
  - `kind` constrained to `credit` or `debit`
- `refresh_tokens`
  - Session persistence and revocation support for JWT refresh flow

## Migrations

1. `migrations/001_init_banking_schema.sql`
   - Creates all four core tables
   - Adds check constraints and foreign keys
   - Adds supporting indexes
2. `migrations/002_seed_initial_data.sql`
   - Seeds three users, three accounts, and initial transactions
   - Uses the same IDs and seed shape as the source repository
3. `migrations/899_unseed_initial_data.sql`
  - Removes only framework-seeded records
4. `migrations/900_down_banking_schema.sql`
  - Drops all framework tables and indexes

## Initialization Order

1. Run `001_init_banking_schema.sql`
2. Run `002_seed_initial_data.sql`

## Automation

- `scripts/init_db.sh`: applies both migrations in order
- `scripts/verify_db.sh`: validates required tables, seed minimums, and referential integrity
- `make db-init`: initialize database file (default `banking.sqlite`)
- `make db-reset`: delete and recreate database file
- `make db-seed`: rerun seed migration only (idempotent)
- `make db-inspect`: print tables and row counts
- `make db-verify`: run validation checks against an initialized database
- `make db-unseed`: delete seed records without dropping schema
- `make db-down`: drop schema objects (tables and indexes)
- `make db-rebuild`: run full teardown then initialize schema + seed
- `make db-report`: generate Markdown health report at `reports/db-health-report.md`
- `.github/workflows/db-pipeline.yml`: daily CI pipeline at 01:00 AM IST
- `.github/workflows/db-weekly-monitor.yml`: weekly monitor at 01:00 AM IST (Monday), opens issue on failure

## Compatibility Notes

- Column names and table relationships are designed to match Banking_Application backend usage patterns.
- Seed credentials in this framework are for local development only.
- Seed migration uses `INSERT OR IGNORE` for safe repeated execution.
- For production use, migrate to hashed passwords before exposing auth endpoints.
