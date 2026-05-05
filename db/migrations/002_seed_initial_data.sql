PRAGMA foreign_keys = ON;

-- Note: Password values are development-only defaults mirrored from source credentials.
-- In production, always store strong password hashes.

INSERT OR IGNORE INTO users (id, full_name, email, password, role, created_at)
VALUES
  ('user-1001', 'Ava Smith', 'ava.smith@novabank.com', 'ava@123', 'customer', '2026-05-01T00:00:00.000Z'),
  ('user-1002', 'Noah Patel', 'noah.patel@novabank.com', 'noah@123', 'customer', '2026-05-01T00:00:00.000Z'),
  ('user-1003', 'Mia Johnson', 'mia.johnson@novabank.com', 'mia@123', 'manager', '2026-05-01T00:00:00.000Z');

INSERT OR IGNORE INTO accounts (id, user_id, type, balance, currency, created_at)
VALUES
  ('acc-1001', 'user-1001', 'checking', 4200, 'USD', '2026-05-01T00:00:00.000Z'),
  ('acc-1002', 'user-1002', 'savings', 8950, 'USD', '2026-05-01T00:00:00.000Z'),
  ('acc-1003', 'user-1003', 'checking', 12400, 'USD', '2026-05-01T00:00:00.000Z');

INSERT OR IGNORE INTO transactions (id, account_id, kind, amount, note, timestamp)
VALUES
  ('txn-9001', 'acc-1001', 'credit', 1200, 'Salary', '2026-05-01T10:00:00.000Z'),
  ('txn-9002', 'acc-1001', 'debit', 300, 'Groceries', '2026-05-02T09:30:00.000Z'),
  ('txn-9003', 'acc-1002', 'credit', 450, 'Interest', '2026-05-03T07:00:00.000Z');
