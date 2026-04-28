-- V1: Initial schema for Contoso Financial reporting database
-- Versioned migration (Flyway/Liquibase compatible naming)

CREATE TABLE IF NOT EXISTS transactions (
    id               BIGSERIAL PRIMARY KEY,
    transaction_date DATE          NOT NULL,
    account_id       VARCHAR(64)   NOT NULL,
    amount           NUMERIC(18,2) NOT NULL,
    currency         CHAR(3)       NOT NULL DEFAULT 'EUR',
    description      TEXT,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Index for the batch job's daily query
CREATE INDEX IF NOT EXISTS idx_transactions_date
    ON transactions (transaction_date);

-- Seed minimal data for local smoke tests
INSERT INTO transactions (transaction_date, account_id, amount, description)
VALUES
    (CURRENT_DATE, 'ACC-001', 1500.00, 'Test transaction A'),
    (CURRENT_DATE, 'ACC-002', -200.50, 'Test transaction B'),
    (CURRENT_DATE, 'ACC-003', 9875.00, 'Test transaction C')
ON CONFLICT DO NOTHING;
