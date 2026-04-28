"""
Discovery regression — Finding W1-2, B2: shared NFS mount replaced by S3.

On-prem both workloads wrote to /mnt/reports/ on a shared NFS mount.
These tests verify that no NFS paths remain in code and that S3 is the write target.
"""
import os
import json
import datetime
import pytest
from conftest import S3_BUCKET_WEBAPP, S3_BUCKET_BATCH


def _abs(relative_path):
    return os.path.join(os.path.dirname(__file__), relative_path)


def test_webapp_source_no_nfs_path():
    """app.py contains no references to /mnt/reports/ (Finding W1-2)."""
    with open(_abs("../workloads/webapp/app.py")) as f:
        code = f.read()
    assert "/mnt/reports" not in code, (
        "Found /mnt/reports reference in app.py — NFS dependency not removed"
    )
    assert "/mnt/" not in code, (
        "Found /mnt/ mount path in app.py — all file I/O must go through S3"
    )


def test_batch_source_no_nfs_path():
    """reconcile.py contains no references to /mnt/ paths (Finding B2)."""
    with open(_abs("../workloads/batch/reconcile.py")) as f:
        code = f.read()
    assert "/mnt/reports" not in code, (
        "Found /mnt/reports reference in reconcile.py — NFS dependency not removed"
    )
    assert "/mnt/" not in code, (
        "Found /mnt/ mount path in reconcile.py — all output must go to S3"
    )


def test_batch_writes_to_s3_not_filesystem(s3_client):
    """Batch output goes to S3 bucket, not local filesystem.

    Validates that the S3 bucket is writable with the expected key pattern.
    """
    # Simulate what the batch job does: write to the deterministic S3 key
    today = datetime.date.today().isoformat()
    key = f"reconciled/{today}/result.json"
    payload = json.dumps({"run_date": today, "records": [], "_test": True})

    s3_client.put_object(Bucket=S3_BUCKET_BATCH, Key=key, Body=payload)
    obj = s3_client.get_object(Bucket=S3_BUCKET_BATCH, Key=key)
    result = json.loads(obj["Body"].read())

    assert result.get("run_date") == today, "S3 write/read round-trip failed"
    # Cleanup test artifact
    s3_client.delete_object(Bucket=S3_BUCKET_BATCH, Key=key)


def test_webapp_s3_bucket_writable(s3_client):
    """Webapp can write PDF reports to S3 (not to /mnt/reports/)."""
    key = "reports/2026/04/discovery-regression-test.pdf"
    s3_client.put_object(
        Bucket=S3_BUCKET_WEBAPP, Key=key,
        Body=b"%PDF-1.4 test", ContentType="application/pdf"
    )
    obj = s3_client.get_object(Bucket=S3_BUCKET_WEBAPP, Key=key)
    assert obj["ContentType"] == "application/pdf"
    s3_client.delete_object(Bucket=S3_BUCKET_WEBAPP, Key=key)
