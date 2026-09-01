DB_FILE ?= banking.sqlite

.PHONY: db-init db-reset db-seed db-inspect db-verify db-unseed db-down db-rebuild db-report scripts-chmod

scripts-chmod:
	chmod +x scripts/init_db.sh scripts/verify_db.sh scripts/generate_db_report.sh

db-init:
	$(MAKE) scripts-chmod
	bash scripts/init_db.sh "$(DB_FILE)"

db-reset:
	$(MAKE) scripts-chmod
	rm -f "$(DB_FILE)"
	bash scripts/init_db.sh "$(DB_FILE)"

db-seed:
	$(MAKE) scripts-chmod
	sqlite3 "$(DB_FILE)" < db/migrations/002_seed_initial_data.sql

db-inspect:
	sqlite3 "$(DB_FILE)" ".tables"
	sqlite3 "$(DB_FILE)" "SELECT 'users' AS table_name, COUNT(*) AS rows FROM users UNION ALL SELECT 'accounts', COUNT(*) FROM accounts UNION ALL SELECT 'transactions', COUNT(*) FROM transactions UNION ALL SELECT 'refresh_tokens', COUNT(*) FROM refresh_tokens;"

db-verify:
	$(MAKE) scripts-chmod
	bash scripts/verify_db.sh "$(DB_FILE)"

db-unseed:
	sqlite3 "$(DB_FILE)" < db/migrations/899_unseed_initial_data.sql

db-down:
	sqlite3 "$(DB_FILE)" < db/migrations/900_down_banking_schema.sql

db-rebuild:
	$(MAKE) db-down DB_FILE="$(DB_FILE)"
	$(MAKE) db-init DB_FILE="$(DB_FILE)"

db-report:
	$(MAKE) scripts-chmod
	bash scripts/generate_db_report.sh "$(DB_FILE)" "reports/db-health-report.md"
	bash scripts/generate_db_report.sh "$(DB_FILE)" "reports/db-health-report.html"
