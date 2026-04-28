# Team TimisA

## Participants
- Antonella Timis (PM · Architect · Dev · Platform · Quality)
- Andrea Curcio (Dev · Platform · Infrastructure · Quality)

## Scenario
Scenario 2: Cloud Migration — "The Lift, the Shift, and the 4am Call"

---

## What We Built

Contoso Financial runs three workloads on-prem: a customer-facing web app, a nightly batch reconciliation job, and a reporting database queried by five internal teams. We built a full set of cloud-ready artifacts that run locally via Docker Compose against cloud-equivalent stand-ins (MinIO→S3, Postgres→RDS, Redis→ElastiCache), deployable to AWS with a config swap and no rebuild.

The strategic decision — **direct cloud-native refactor rather than lift-and-shift** — is backed by a cost/time/benefit analysis showing net savings of **€19,500 over 24 months** with only a 2-week delay. Every architecture choice is documented in an immutable ADR and traceable to a specific discovery finding.

The discovery surfaced **5 critical blockers**, including a silent batch→webapp dependency unknown to the dev team, and plaintext DB credentials unchanged for 7 years. All 5 resolved before containerisation.

**What runs:**
- `docker compose up` brings up all five services (postgres, redis, minio, webapp, batch) with health checks
- `pytest tests/` runs a 3-stage gated validation suite (smoke → contract → discovery regressions)
- `python scorecard/eval.py` scores Claude's Terraform against 20 good-pattern + 15 bad-pattern checks — our IaC scores **96%, Grade A**
- A `PreToolUse` hook deterministically blocks any Claude edit writing a plaintext secret into IaC or source code

**What's IaC (not deployed live):** Seven Terraform modules covering the full AWS target architecture — networking, storage, secrets, cache, database, webapp, batch.

---

## Challenges Attempted

| # | Challenge | Status | Notes |
|---|-----------|--------|-------|
| 1 | The Memo | done | Strategic decision: cloud-native refactor. Cost/benefit: €19,500 net saving over 24 months. `docs/memo.md` |
| 2 | The Discovery | done | 5 blockers surfaced (W1-1, W1-2, W1-3, B1, B2, B4). Hardcoded IPs, NFS mount, disk sessions, cron coupling, plaintext creds. `docs/discovery.md` |
| 3 | The Options + ADRs | done | 8 ADRs accepted. ECS Fargate + AWS Batch, RDS Multi-AZ + Read Replica + Proxy, ElastiCache, Secrets Manager rotation. `docs/adr/` |
| 4 | The Container | done | Multi-stage Dockerfile, non-root user, health check, gunicorn. Same image deploys locally and to ECS. `workloads/` |
| 5 | The Foundation | done | 7 Terraform modules. No hardcoded secrets. S3 backend story. `PreToolUse` hook blocks secret writes. `infra/` |
| 6 | The Proof | done | 3-stage gated suite: smoke, contract, data integrity, discovery regressions. Each test maps to a named finding. `tests/` |
| 7 | The Scorecard | done | `eval.py`: 20 good-pattern + 15 bad-pattern detectors. Self-test 100%. IaC score 96% Grade A. CI in GitHub Actions. `scorecard/` |
| 8 | The Undo | skipped | |
| 9 | The Survey | skipped | |

---

## Key Decisions

**Refactor cloud-native, not lift-and-shift** — The 2-week timeline delta buys a €19,500 saving by skipping the second refactor project lift-and-shift makes inevitable. `docs/memo.md`, `docs/analisi-costi-tempi-benefici.md`

**Every discovery blocker has an ADR and a regression test** — Nothing from `docs/discovery.md` is accepted and forgotten. Each of the 5 blockers has an ADR documenting the fix and a pytest assertion verifying it. If the fix regresses, the test catches it before cutover.

**Hooks for deterministic guardrails, prompts for preferences** — The `PreToolUse` hook exits 1 on any plaintext secret pattern. `CLAUDE.md` says "prefer Secrets Manager" for probabilistic guidance. ADR-0003 documents why each mechanism is what it is.

**Compute: ECS Fargate + AWS Batch** — Fargate for the web app (stateless, autoscaling 2–6 tasks), Batch for the nightly job (pay-per-execution, no 22h idle EC2). `docs/adr/0006-compute-target-ecs-fargate-aws-batch.md`

**RDS Proxy in front of the database** — 5 teams query the reporting DB. Without connection pooling, the first load spike exhausts Postgres connections. The proxy adds ~€30/month and prevents the 4am call. `docs/adr/0007-rds-multi-az-read-replica-rds-proxy.md`

**Idempotent batch job (S3 PutObject, DB upsert)** — The nightly reconciliation can be re-run safely with no duplicates or appended files. `docs/adr/0008-batch-idempotency.md`. Validated by `tests/data_integrity/test_batch_idempotency.py`.

---

## How to Run It

**Prerequisites:** Docker, Docker Compose, Python 3.11+

```bash
# 1. Start the local stack
cd TimisA
docker compose up -d postgres redis minio webapp
docker compose ps   # wait until all services healthy (~30s)

# 2. Run the full validation suite
cd tests
pip install -r requirements.txt
./run_tests.sh
# Reports written to tests/reports/results-<timestamp>.json

# 3. Run the IaC scorecard
cd ../scorecard
python eval.py
# Scores TimisA/infra/ against 20 good-pattern + 15 bad-pattern checks
```

**Cloud run** (set env vars, same suite):
```bash
export WEBAPP_URL=https://your-cloudfront-domain.com
export DB_HOST=contoso-db-proxy-prod.proxy-xxx.eu-west-1.rds.amazonaws.com
# ... see tests/RUNBOOK.md for full cloud env var list
cd tests && ./run_tests.sh
```

---

## Architecture

```
Users ──► CloudFront ──► ALB ──► ECS Fargate (Web App)
                                      │         │
                                 ElastiCache  S3 Reports
                                  (Sessions)  (ADR-0002)
                                      │
                                 RDS Proxy ──► RDS Primary (Multi-AZ)
                                                   │
                                              Read Replica
                                                   ▲
EventBridge (02:00 UTC) ──► AWS Batch Job ─────────┘
                                 │
                          S3 Batch Output
```

All infrastructure is in `infra/` as Terraform modules. No secrets in IaC — credentials live in Secrets Manager with 180-day auto-rotation.

---

## If We Had More Time

1. **Waypoint 8 — Rollback plan:** Per-workload, per-stage rollback sequences. The one nobody wants to write but everyone needs at 4am.
2. **Waypoint 9 — Agentic survey:** Parallel discovery with Task subagents (one per workload), coordinator merges into a single doc, surfaces cross-workload couplings a single-pass analysis misses.
3. **MCP server over the local stack:** Tool descriptions that teach a fresh Claude session what MinIO is not — so it doesn't hallucinate S3-only features against the stand-in.
4. **Terraform plan validation in CI:** Run `terraform validate` and `terraform plan` against a localstack or mock provider in GitHub Actions, not just the pattern scanner.
5. **Monitoring runbook:** CloudWatch alarms + SNS for the batch job — CTO go-live condition.

---

## How We Used Claude Code

Claude Code accompanied every phase of the project as an active technical collaborator.

**Where it saved the most time:** Translating 8 ADRs directly into Terraform — each module was scaffolded in one shot with the ADR as context. Without Claude, the IaC would have taken most of the day. With it, all 7 modules were done in under an hour.

**What worked:**
- `CLAUDE.md` per workload directory (webapp, batch, reporting-db) — Claude stayed in character for each folder and didn't bleed conventions across workloads
- `PreToolUse` hook for secrets — zero plaintext credentials in any generated file, no manual review needed
- Discovery findings as test specs — handing Claude `discovery.md` and asking for regression tests produced assertions that directly named each finding (W1-1, B4, etc.) rather than generic smoke tests
- Scorecard as self-critique — running `eval.py` against our own IaC found gaps before we pushed
- Stakeholder simulation — Claude role-played CFO and CTO objections to pressure-test the architecture recommendation before the real meeting

**What surprised us:**
- Claude correctly inferred that the batch job needed an EventBridge warmup trigger 5 minutes before the main schedule (ADR-0005) without being explicitly told — it read `discovery.md` and connected the dots
- The 3-stage gated test runner structure was proposed by Claude after seeing the RUNBOOK format — we just agreed
- Plan Mode for the Terraform module dependency graph prevented a circular reference we would have hit at `terraform apply`

**Where it needed steering:**
- First attempt at the webapp Dockerfile used `curl` for the health check — `python:3.12-slim` doesn't include curl. Fixed immediately once pointed out.
- IaC scorecard initially flagged egress rules and VPC CIDRs as bad patterns — needed one round of regex tuning to scope the checks correctly.
