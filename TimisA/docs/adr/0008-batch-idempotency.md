# ADR-0008 — Batch Job Idempotency

**Status:** Accepted  
**Date:** 2026-04-28  
**Deciders:** Team TimisA  

---

## Context

Discovery (Finding B3) found that the reconciliation batch job appends to existing output files rather than overwriting. Re-running the job on the same date window produces duplicate records.

This is not a cloud blocker per se, but it is a correctness blocker: AWS Batch retries failed jobs automatically (up to a configurable number of attempts). Without idempotency, a retry on a partially-failed run will duplicate already-processed records, producing incorrect reconciliation output.

On-prem this risk was managed by "don't re-run it" — an acceptable workaround when there is a single VM and a single ops person. In cloud, where retries are automatic and infrastructure is ephemeral, it is not acceptable.

---

## Decision

Rewrite the batch job output logic to be fully idempotent: running the job multiple times on the same date window produces the same output as running it once.

**Pattern:**

```python
# Output key includes date window — deterministic, same run = same key
output_key = f"reconciled/{year}/{month}/{date}/output.csv"

# Write to S3 with explicit overwrite (S3 PutObject is naturally idempotent)
s3.put_object(
    Bucket="contoso-batch-output-prod",
    Key=output_key,
    Body=csv_content
)
```

S3 `PutObject` is inherently idempotent — writing to the same key overwrites the previous object. No append logic, no state tracking needed.

**For DB writes (reconciliation status updates):**
```sql
INSERT INTO reconciliation_runs (run_date, status, output_s3_key)
VALUES (%s, %s, %s)
ON CONFLICT (run_date) DO UPDATE
SET status = EXCLUDED.status,
    output_s3_key = EXCLUDED.output_s3_key,
    updated_at = NOW();
```

Upsert instead of insert — re-running on the same date updates the existing record rather than duplicating it.

**AWS Batch retry configuration:** max 2 automatic retries on job failure. With idempotency in place, retries are safe.

---

## Consequences

**Positive:**
- AWS Batch automatic retries are safe — ops no longer needs to manually verify before re-running
- Partial failures mid-job can be safely retried without data corruption
- Output files on S3 are deterministic — the same run always produces the same file at the same key

**Negative:**
- Small refactor of output writing logic required
- Existing append-based output files on the NFS mount (being decommissioned per ADR-0002) do not need migration — they are considered historical records and archived as-is

---

## Implementation Checklist

- [ ] Replace file-append logic with S3 `put_object` (deterministic key per date window)
- [ ] Replace `INSERT` for reconciliation status with `INSERT ... ON CONFLICT DO UPDATE`
- [ ] Set AWS Batch job retry count to 2
- [ ] Add integration test: run job twice on same date window, assert output is identical
- [ ] Add integration test: simulate mid-job failure, assert retry produces correct output
