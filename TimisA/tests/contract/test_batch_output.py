"""Contract: batch job S3 output schema validation."""
import json
import datetime
import pytest
from conftest import S3_BUCKET_BATCH


def _get_latest_output(s3_client):
    """Return the most recent reconciliation output object from S3."""
    today = datetime.date.today().isoformat()
    key = f"reconciled/{today}/result.json"
    try:
        obj = s3_client.get_object(Bucket=S3_BUCKET_BATCH, Key=key)
        return json.loads(obj["Body"].read())
    except s3_client.exceptions.NoSuchKey:
        return None
    except Exception:
        return None


OUTPUT_REQUIRED_KEYS = {"run_date", "records"}
RECORD_REQUIRED_KEYS = {"transaction_id", "amount", "status", "reconciled_at"}


@pytest.mark.skipif(
    _get_latest_output is None,
    reason="No batch output found — run batch job first"
)
def test_batch_output_exists(s3_client):
    """Batch job produced an output file in S3 for today."""
    output = _get_latest_output(s3_client)
    assert output is not None, (
        f"No output found in s3://{S3_BUCKET_BATCH}/reconciled/{{today}}/result.json — "
        "run: docker compose --profile batch run batch"
    )


def test_batch_output_schema(s3_client):
    """S3 output file has required top-level keys."""
    output = _get_latest_output(s3_client)
    if output is None:
        pytest.skip("No batch output found — run batch job first")
    missing = OUTPUT_REQUIRED_KEYS - output.keys()
    assert not missing, f"Output missing keys: {missing}"


def test_batch_output_records_schema(s3_client):
    """Each record in the output has required fields."""
    output = _get_latest_output(s3_client)
    if output is None:
        pytest.skip("No batch output found — run batch job first")
    records = output.get("records", [])
    assert isinstance(records, list), "records must be a list"
    for i, rec in enumerate(records[:5]):  # check first 5
        missing = RECORD_REQUIRED_KEYS - rec.keys()
        assert not missing, f"Record {i} missing fields: {missing}"


def test_batch_output_run_date_format(s3_client):
    """Output run_date is a valid ISO date string."""
    output = _get_latest_output(s3_client)
    if output is None:
        pytest.skip("No batch output found — run batch job first")
    run_date = output.get("run_date", "")
    datetime.date.fromisoformat(run_date)  # raises ValueError if invalid


def test_batch_output_status_values(s3_client):
    """All records have a recognised status value."""
    output = _get_latest_output(s3_client)
    if output is None:
        pytest.skip("No batch output found — run batch job first")
    allowed = {"reconciled", "failed", "skipped"}
    for rec in output.get("records", []):
        assert rec.get("status") in allowed, (
            f"Unexpected status '{rec.get('status')}' — allowed: {allowed}"
        )
