# Test Runbook — Contoso Financial Cloud Migration
## Challenge 6: The Proof

---

## Prerequisites

```bash
cd TimisA/tests
pip install -r requirements.txt
```

**Local stack must be running:**
```bash
cd TimisA
docker compose up -d postgres redis minio webapp
# Wait for all services healthy (~30s)
docker compose ps
```

---

## Execution — Full Suite (Recommended)

```bash
cd TimisA/tests
./run_tests.sh
```

Results written to `tests/reports/results-<timestamp>.json`.

---

## Stage Breakdown & Gates

### Stage 1 — Smoke
**Run:** `pytest smoke/ -v`
**Gate:** All 3 backing services (Postgres, Redis, MinIO) healthy + webapp returns 200.

| Test | Validates |
|------|-----------|
| `test_postgres_connects` | DB reachable, migration applied |
| `test_redis_ping` | Session store available |
| `test_s3_reachable` | Object storage available |
| `test_webapp_health_status_healthy` | All checks green before functional tests |

> **⛔ If Stage 1 fails:** Do not proceed. Fix infrastructure before running further tests.

---

### Stage 2 — Contract + Data Integrity
**Run:** `pytest contract/ data_integrity/ -v`
**Gate:** API schemas correct, DB schema valid, idempotency proven.

| Test | Validates |
|------|-----------|
| `test_health_schema_complete` | /health response has all required fields |
| `test_warmup_endpoint_schema` | /api/warmup returns `{warmed: true}` |
| `test_no_server_header_leaks` | Gunicorn in use (not dev server) |
| `test_transactions_columns` | DB migration ran correctly |
| `test_transactions_index_on_date` | Query performance index present |
| `test_s3_put_object_is_idempotent` | S3 overwrites, does not append (ADR-0008) |
| `test_db_upsert_not_insert` | Reconciliation upsert is idempotent (ADR-0008) |

> **⛔ If Stage 2 fails:** Do not proceed to cutover. Fix schema or application issues.

---

### Stage 3 — Discovery Regressions ⭐
**Run:** `pytest discovery/ -v`
**Gate:** All 5 Discovery blockers resolved. This gate directly validates the undocumented hazards found in Challenge 2.

| Test | Discovery Finding | What it catches |
|------|------------------|-----------------|
| `test_webapp_source_no_hardcoded_ip` | W1-1 | `DB_HOST=10.0.1.82` in app.py |
| `test_batch_source_no_hardcoded_credentials` | B4 | `password=C0nt0s0#2019` in reconcile.py |
| `test_db_host_is_hostname_not_ip` | W1-1 | Runtime DB_HOST is a DNS name, not an IP |
| `test_webapp_source_no_nfs_path` | W1-2 | `/mnt/reports/` removed from webapp |
| `test_batch_source_no_nfs_path` | B2 | `/mnt/reports/` removed from batch job |
| `test_batch_writes_to_s3_not_filesystem` | B2 | S3 bucket writable with correct key pattern |
| `test_warmup_endpoint_callable` | B1 | `/api/warmup` reachable on demand (not cron) |
| `test_warmup_sets_redis_key` | B1 | Warmup writes to Redis (not in-process cache) |
| `test_batch_source_no_curl_warmup` | B1 | No curl/warmup call in batch source |
| `test_webapp_source_no_flask_session_disk` | W1-3 | `/tmp/flask_sessions/` removed |
| `test_redis_session_key_ttl` | W1-3 | Redis keys expire (no unbounded growth) |

> **⛔ If Stage 3 fails:** Do not cut over. A Discovery blocker is still present.
> **✅ If Stage 3 passes:** CUTOVER APPROVED for the validated workload.

---

## Cloud Run

Set environment variables, then run the same suite:

```bash
export WEBAPP_URL=https://your-cloudfront-domain.com
export DB_HOST=contoso-db-proxy-prod.proxy-xxx.eu-west-1.rds.amazonaws.com
export DB_NAME=contoso
export DB_USER=contoso_app
export DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id contoso/prod/db-credentials \
  --query SecretString --output text | python -c "import sys,json; print(json.load(sys.stdin)['password'])")
export REDIS_URL=rediss://contoso-webapp-cache-prod.xxx.cache.amazonaws.com:6379/0
export S3_ENDPOINT=   # leave empty for real AWS
export S3_BUCKET_WEBAPP=contoso-webapp-reports-prod
export S3_BUCKET_BATCH=contoso-batch-output-prod

cd TimisA/tests
./run_tests.sh
```

---

## Results Artifact

Each run produces:
- `reports/smoke-<timestamp>.json`
- `reports/contract-<timestamp>.json`
- `reports/data_integrity-<timestamp>.json`
- `reports/discovery-<timestamp>.json`
- `reports/results-<timestamp>.json` ← merged summary

The merged summary includes per-stage pass/fail counts, test names, durations, and failure messages. Attach to the cutover sign-off ticket.
