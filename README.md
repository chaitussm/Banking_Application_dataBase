# Banking_Application_dataBase

Database framework repository derived from the `Banking_Application` backend data model.

## What Was Fetched From Banking_Application

The following required database details were pulled into this framework:

- Core tables: `users`, `accounts`, `transactions`, `refresh_tokens`
- User auth fields: `password`, `failed_login_attempts`, `locked_until`, `role`
- Account ownership model: `accounts.user_id -> users.id`
- Transaction model: account-scoped credit/debit entries with timestamps
- Session model: refresh token storage and revocation tracking
- Seeded domain data:
	- Users: `user-1001`, `user-1002`, `user-1003`
	- Accounts: `acc-1001`, `acc-1002`, `acc-1003`
	- Transactions: `txn-9001`, `txn-9002`, `txn-9003`

## Repository Structure

- `db/migrations/001_init_banking_schema.sql`: Schema creation + constraints + indexes
- `db/migrations/002_seed_initial_data.sql`: Initial seed records
- `db/migrations/899_unseed_initial_data.sql`: Removes only seeded records
- `db/migrations/900_down_banking_schema.sql`: Drops all framework tables and indexes
- `db/README.md`: Entity-level framework notes

## Apply Migrations

Example using SQLite CLI:

```bash
sqlite3 banking.sqlite < db/migrations/001_init_banking_schema.sql
sqlite3 banking.sqlite < db/migrations/002_seed_initial_data.sql
```

Or run the one-command bootstrap:

```bash
make db-init
```

Use a custom database file path:

```bash
make db-init DB_FILE=dev-banking.sqlite
```

Reset and recreate:

```bash
make db-reset
```

Inspect tables and row counts:

```bash
make db-inspect
```

Verify schema and seed integrity:

```bash
make db-verify
```

Run seed data safely multiple times (idempotent):

```bash
make db-seed
```

Rollback only seeded data:

```bash
make db-unseed
```

Drop full schema and indexes:

```bash
make db-down
```

Drop and recreate everything in one step:

```bash
make db-rebuild
```

Generate a database health report:

```bash
make db-report
```

## CI Pipeline And Daily Schedule

- Workflow file: `.github/workflows/db-pipeline.yml`
- Triggers:
	- Push to `master`
	- Pull request to `master`
	- Manual run (`workflow_dispatch`)
	- Scheduled daily run at `01:00 AM IST`
- Cron used in GitHub Actions (UTC): `30 19 * * *`

Pipeline steps:

1. Rebuild database (`make db-rebuild`)
2. Verify schema and integrity (`make db-verify`)
3. Generate report (`make db-report`)
4. Upload artifacts:
	 - `reports/db-health-report.md`
	 - `reports/db-health-report.html` (responsive, self-contained health dashboard)
	 - `ci-banking.sqlite`

## Weekly Monitoring Pipeline

- Workflow file: `.github/workflows/db-weekly-monitor.yml`
- Triggers:
	- Manual run (`workflow_dispatch`)
	- Scheduled weekly run at `01:00 AM IST` every Monday
- Cron used in GitHub Actions (UTC): `30 19 * * 0` (Sunday UTC evening)

Weekly pipeline behavior:

1. Rebuild database
2. Run verification checks
3. Generate/upload Markdown and responsive HTML health report artifacts
4. If verification fails, automatically create a GitHub issue with run link and context
5. Duplicate protection: if an open weekly monitor failure issue already exists, workflow reuses it and does not open another one

## Notes

- This framework is intentionally compatible with the source Banking_Application model.
- Seed passwords are development-only values.
- Seed migration is idempotent (`INSERT OR IGNORE`) so reruns do not fail on existing rows.
- SQLite artifacts are ignored through `.gitignore` to keep repository commits clean.
- For production, replace plain password values with hashed values and enforce stronger security policies.