"""
Nightly reconciliation job — Contoso Financial.

Fixes applied vs on-prem version (see docs/discovery.md):
  B1: cache warm-up decoupled (EventBridge triggers webapp directly in cloud)
  B2: output goes to S3, not NFS mount
  B3: upsert logic — idempotent on same RUN_DATE
  B4: credentials from env vars, never hardcoded
"""
import os
import sys
import json
import logging
from datetime import date, datetime
import psycopg2
import psycopg2.extras
import boto3
from botocore.client import Config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,  # CloudWatch captures stdout
)
log = logging.getLogger(__name__)


def _db_conn():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", 5432)),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        cursor_factory=psycopg2.extras.RealDictCursor,
    )


def _s3_client():
    kwargs = dict(
        region_name=os.environ.get("AWS_REGION", "eu-west-1"),
    )
    endpoint = os.environ.get("S3_ENDPOINT")
    if endpoint:
        # Local: MinIO stand-in
        kwargs["endpoint_url"] = endpoint
        kwargs["config"] = Config(signature_version="s3v4")
    return boto3.client("s3", **kwargs)


def fetch_transactions(conn, run_date: date) -> list:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT * FROM transactions WHERE transaction_date = %s",
            (run_date,),
        )
        return cur.fetchall()


def reconcile(transactions: list) -> list:
    """Business logic placeholder — returns reconciliation records."""
    return [
        {
            "transaction_id": str(t["id"]),
            "amount": float(t["amount"]),
            "status": "reconciled",
            "reconciled_at": datetime.utcnow().isoformat(),
        }
        for t in transactions
    ]


def upload_result(s3, run_date: date, records: list) -> str:
    bucket = os.environ["S3_BUCKET"]
    key = f"reconciled/{run_date.isoformat()}/result.json"
    body = json.dumps({"run_date": run_date.isoformat(), "records": records}, indent=2)
    s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType="application/json")
    return f"s3://{bucket}/{key}"


def ensure_bucket(s3):
    bucket = os.environ["S3_BUCKET"]
    try:
        s3.head_bucket(Bucket=bucket)
    except Exception:
        s3.create_bucket(Bucket=bucket)


def main():
    run_date_str = os.environ.get("RUN_DATE") or date.today().isoformat()
    run_date = date.fromisoformat(run_date_str)
    log.info("Starting reconciliation for %s", run_date)

    conn = _db_conn()
    s3 = _s3_client()
    ensure_bucket(s3)

    try:
        transactions = fetch_transactions(conn, run_date)
        log.info("Fetched %d transactions", len(transactions))

        records = reconcile(transactions)
        s3_path = upload_result(s3, run_date, records)
        log.info("Result uploaded to %s", s3_path)

    finally:
        conn.close()

    log.info("Reconciliation complete")


if __name__ == "__main__":
    main()
