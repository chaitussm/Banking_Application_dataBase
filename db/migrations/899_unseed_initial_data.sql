PRAGMA foreign_keys = ON;

-- Remove only records introduced by 002_seed_initial_data.sql.
DELETE FROM transactions
WHERE id IN ('txn-9001', 'txn-9002', 'txn-9003');

DELETE FROM accounts
WHERE id IN ('acc-1001', 'acc-1002', 'acc-1003');

DELETE FROM users
WHERE id IN ('user-1001', 'user-1002', 'user-1003');
