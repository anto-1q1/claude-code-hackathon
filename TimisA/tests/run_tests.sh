#!/usr/bin/env bash
# Contoso Financial — Migration Validation Suite
# Runs in 3 gated stages. A failure in any stage halts progression.
# Usage:
#   ./run_tests.sh                  # local (Docker Compose defaults)
#   ./run_tests.sh --env cloud      # cloud (reads env vars from environment)
#
# Required env vars for cloud run:
#   WEBAPP_URL, DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD,
#   REDIS_URL, S3_ENDPOINT (leave unset for real AWS), S3_BUCKET_WEBAPP,
#   S3_BUCKET_BATCH, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

set -euo pipefail

REPORT_DIR="reports"
TIMESTAMP=$(date +%Y%m%dT%H%M%S)
REPORT_FILE="${REPORT_DIR}/results-${TIMESTAMP}.json"
PASS=0
FAIL=1

mkdir -p "${REPORT_DIR}"

run_stage() {
  local stage_name="$1"
  local test_path="$2"
  local gate_label="$3"

  echo ""
  echo "══════════════════════════════════════════════════"
  echo "  STAGE: ${stage_name}"
  echo "══════════════════════════════════════════════════"

  python -m pytest "${test_path}" \
    --tb=short \
    --json-report \
    --json-report-file="${REPORT_DIR}/${stage_name}-${TIMESTAMP}.json" \
    -v

  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo ""
    echo "✗ GATE FAILED: ${gate_label}"
    echo "  Stage '${stage_name}' has failures. Do NOT proceed to next cutover phase."
    echo "  Report: ${REPORT_DIR}/${stage_name}-${TIMESTAMP}.json"
    exit $exit_code
  fi

  echo ""
  echo "✓ GATE PASSED: ${gate_label}"
}

echo "╔══════════════════════════════════════════════════╗"
echo "║  Contoso Financial — Migration Validation Suite  ║"
echo "╚══════════════════════════════════════════════════╝"
echo "  Timestamp : ${TIMESTAMP}"
echo "  WEBAPP_URL: ${WEBAPP_URL:-http://localhost:5000}"
echo "  DB_HOST   : ${DB_HOST:-localhost}"
echo ""

# ── Stage 1: Smoke ────────────────────────────────────────────────────────────
run_stage "smoke" "smoke/" \
  "All backing services healthy — safe to run functional tests"

# ── Stage 2: Contract + Data Integrity ───────────────────────────────────────
run_stage "contract" "contract/" \
  "API contracts met — safe to run discovery regressions"

run_stage "data_integrity" "data_integrity/" \
  "Data integrity confirmed — schema and idempotency correct"

# ── Stage 3: Discovery Regressions ───────────────────────────────────────────
run_stage "discovery" "discovery/" \
  "All Discovery blockers resolved — CUTOVER APPROVED"

# ── Merge all reports into single artifact ────────────────────────────────────
python - <<'EOF'
import json, glob, sys, os

reports = []
for f in sorted(glob.glob("reports/*.json")):
    if "results-" in f:
        continue
    with open(f) as fh:
        reports.append({"stage": os.path.basename(f), "data": json.load(fh)})

summary = {
    "timestamp": os.environ.get("TIMESTAMP", ""),
    "webapp_url": os.environ.get("WEBAPP_URL", "http://localhost:5000"),
    "stages": reports,
    "overall": "PASSED" if all(
        r["data"].get("summary", {}).get("failed", 1) == 0
        for r in reports
    ) else "FAILED"
}

out = f"reports/results-{os.environ.get('TIMESTAMP', 'latest')}.json"
with open(out, "w") as fh:
    json.dump(summary, fh, indent=2)
print(f"\nFull report: {out}")
EOF

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ALL STAGES PASSED — CUTOVER APPROVED            ║"
echo "╚══════════════════════════════════════════════════╝"
