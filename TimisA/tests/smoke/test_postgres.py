"""Smoke: PostgreSQL connectivity and basic readiness."""
import pytest


def test_postgres_connects(db_conn):
    """DB is reachable and accepts connections."""
    cur = db_conn.cursor()
    cur.execute("SELECT 1")
    assert cur.fetchone()[0] == 1
    cur.close()


def test_postgres_correct_database(db_conn):
    """Connected to the expected database, not a default."""
    cur = db_conn.cursor()
    cur.execute("SELECT current_database()")
    assert cur.fetchone()[0] == "contoso"
    cur.close()


def test_postgres_transactions_table_exists(db_conn):
    """Core table exists — migration was applied."""
    cur = db_conn.cursor()
    cur.execute("""
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'transactions'
    """)
    assert cur.fetchone()[0] == 1, "Table 'transactions' not found — migration may not have run"
    cur.close()
