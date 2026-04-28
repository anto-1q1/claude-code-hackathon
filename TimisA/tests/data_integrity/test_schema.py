"""Data integrity: DB schema validation — tables, columns, indexes."""
import pytest


EXPECTED_COLUMNS = {
    "id", "transaction_date", "account_id",
    "amount", "currency", "description", "created_at"
}

EXPECTED_INDEX = "idx_transactions_date"


def test_transactions_table_exists(db_conn):
    """transactions table is present in public schema."""
    cur = db_conn.cursor()
    cur.execute("""
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'transactions'
    """)
    assert cur.fetchone()[0] == 1
    cur.close()


def test_transactions_columns(db_conn):
    """transactions table has all expected columns."""
    cur = db_conn.cursor()
    cur.execute("""
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'transactions'
    """)
    actual = {row[0] for row in cur.fetchall()}
    missing = EXPECTED_COLUMNS - actual
    assert not missing, f"Missing columns: {missing}"
    cur.close()


def test_transactions_index_on_date(db_conn):
    """Index on transaction_date exists — required for batch job query performance."""
    cur = db_conn.cursor()
    cur.execute("""
        SELECT COUNT(*) FROM pg_indexes
        WHERE tablename = 'transactions' AND indexname = %s
    """, (EXPECTED_INDEX,))
    assert cur.fetchone()[0] == 1, (
        f"Index '{EXPECTED_INDEX}' missing — batch queries will full-scan the table"
    )
    cur.close()


def test_seed_data_present(db_conn):
    """Seed rows are present — local stack is initialised."""
    cur = db_conn.cursor()
    cur.execute("SELECT COUNT(*) FROM transactions")
    count = cur.fetchone()[0]
    assert count > 0, "No rows in transactions — migration seed may not have run"
    cur.close()


def test_no_null_account_ids(db_conn):
    """No rows have a NULL account_id — referential integrity check."""
    cur = db_conn.cursor()
    cur.execute("SELECT COUNT(*) FROM transactions WHERE account_id IS NULL")
    assert cur.fetchone()[0] == 0, "Found rows with NULL account_id"
    cur.close()


def test_amount_is_numeric(db_conn):
    """amount column stores numeric values, not strings."""
    cur = db_conn.cursor()
    cur.execute("""
        SELECT data_type FROM information_schema.columns
        WHERE table_name = 'transactions' AND column_name = 'amount'
    """)
    dtype = cur.fetchone()[0]
    assert dtype in ("numeric", "decimal"), f"Unexpected type for amount: {dtype}"
    cur.close()
