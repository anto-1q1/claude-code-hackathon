"""Smoke: S3/MinIO connectivity and bucket availability."""
import pytest
from conftest import S3_BUCKET_WEBAPP, S3_BUCKET_BATCH


def test_s3_reachable(s3_client):
    """S3 endpoint responds to list_buckets."""
    response = s3_client.list_buckets()
    assert "Buckets" in response


def _ensure_bucket(s3_client, bucket_name):
    existing = [b["Name"] for b in s3_client.list_buckets()["Buckets"]]
    if bucket_name not in existing:
        s3_client.create_bucket(Bucket=bucket_name)


def test_webapp_bucket_accessible(s3_client):
    """Webapp reports bucket is accessible."""
    _ensure_bucket(s3_client, S3_BUCKET_WEBAPP)
    s3_client.head_bucket(Bucket=S3_BUCKET_WEBAPP)


def test_batch_bucket_accessible(s3_client):
    """Batch output bucket is accessible."""
    _ensure_bucket(s3_client, S3_BUCKET_BATCH)
    s3_client.head_bucket(Bucket=S3_BUCKET_BATCH)


def test_s3_write_read_delete(s3_client):
    """S3 supports PutObject / GetObject / DeleteObject round-trip."""
    _ensure_bucket(s3_client, S3_BUCKET_WEBAPP)
    key = "smoke-test/probe.txt"
    s3_client.put_object(Bucket=S3_BUCKET_WEBAPP, Key=key, Body=b"ok")
    obj = s3_client.get_object(Bucket=S3_BUCKET_WEBAPP, Key=key)
    assert obj["Body"].read() == b"ok"
    s3_client.delete_object(Bucket=S3_BUCKET_WEBAPP, Key=key)
