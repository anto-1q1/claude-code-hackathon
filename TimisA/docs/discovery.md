# Discovery Report — Contoso Financial
**Prepared by:** Team TimisA  
**Date:** 2026-04-28  
**Method:** Stakeholder interviews (SRE Lead, DBA, Dev Lead, Ops) + direct config inspection  

---

## Executive Summary

Three workloads exist on paper. Six dependencies exist in production. None of the six are documented. Two of them are blockers for migration if not resolved before cutover.

---

## Workload 1 — Customer-Facing Web App

### What the docs say
- Python/Flask application
- Runs on a single VM (`10.0.1.45`)
- Nginx reverse proxy in front
- Connects to the reporting database for customer portfolio data

### What we actually found

**Finding W1-1 — Hardcoded IP in application config**  
`config/production.ini` line 47:
```
DB_HOST=10.0.1.82
```
This is the on-prem IP of the reporting database. No DNS. No environment variable. The app will fail silently at startup on any other network.  
**Impact:** Blocker. Must be resolved before containerization.

**Finding W1-2 — Shared filesystem mount for PDF reports**  
The web app writes generated PDF reports to `/mnt/reports/` — a NFS mount shared with the reporting database VM. Five internal users download reports directly from that mount via a mapped network drive.  
**Impact:** Blocker. NFS mounts don't exist in cloud. Reports must move to S3.

**Finding W1-3 — Session state on local disk**  
Flask sessions are stored in `/tmp/flask_sessions/` on the VM. No Redis, no external session store.  
**Impact:** Stateful container — horizontal scaling impossible until sessions move to ElastiCache.

**Finding W1-4 — Static assets served by the app, not Nginx**  
Despite Nginx being in front, static assets (JS, CSS, images) are served directly by Flask via `send_from_directory`. Nginx is essentially a TCP proxy only.  
**Impact:** Inefficient but not a blocker. Move statics to S3+CloudFront during containerization.

---

## Workload 2 — Nightly Batch Reconciliation Job

### What the docs say
- Python script, runs via cron at 02:00 every night
- Reads transactions from the reporting database
- Writes reconciliation output to a shared folder

### What we actually found

**Finding B1 — Cron pings web app to warm cache**  
`/etc/cron.d/reconciliation`:
```
55 01 * * * curl -s http://10.0.1.45/api/warmup > /dev/null
```
The batch job hits the web app 5 minutes before running to force a cache warm-up of portfolio data. No one on the dev team knew this. The SRE lead discovered it after a web app restart caused a batch failure in 2023.  
**Impact:** Cross-workload coupling. If web app and batch migrate independently, this cron breaks silently.

**Finding B2 — Output written to the same NFS mount**  
Reconciliation output goes to `/mnt/reports/reconciled/` — the same shared NFS mount as the web app. The reporting team picks it up manually every morning.  
**Impact:** Blocker. Same as W1-2 — NFS must be replaced by S3.

**Finding B3 — No idempotency**  
The batch script appends to existing output files rather than overwriting. Rerunning on the same date window duplicates records.  
**Impact:** Must be fixed during migration (not a cloud blocker, but a correctness blocker).

**Finding B4 — Hardcoded DB credentials in script**  
`reconcile.py` line 12:
```python
conn = psycopg2.connect("host=10.0.1.82 user=batch_user password=C0nt0s0#2019")
```
Plaintext password, hardcoded IP, no rotation in 7 years.  
**Impact:** Security blocker. Credentials must move to AWS Secrets Manager before any cloud deployment.

---

## Workload 3 — Reporting Database

### What the docs say
- PostgreSQL 13, single instance
- Queried by 5 internal teams
- Nightly backup to tape

### What we actually found

**Finding R1 — Five teams, five different access patterns**  
Stakeholder interviews revealed:

| Team | Access method | Frequency | Avg query time |
|------|--------------|-----------|----------------|
| Finance | Direct psql, ad-hoc | Continuous | 45 sec |
| Risk | JDBC via Tableau | Every 30 min | 2–8 min |
| Ops | Python scripts, scheduled | Hourly | 15 sec |
| Compliance | Read-only user, manual | Weekly | 20 min |
| Executive | Tableau dashboard | Real-time | 3–5 min |

Finance and Risk run heavy analytical queries that block write operations. This is why the web app occasionally times out during business hours — nobody connected the two.  
**Impact:** Read replica is not optional — it is the fix for an existing production issue.

**Finding R2 — No connection pooling**  
Each application connects directly to Postgres with its own persistent connection. Current connection count at peak: 47. PostgreSQL max_connections: 100. Headroom: 53.  
**Impact:** Migrations to cloud must include PgBouncer or RDS Proxy, or the first load spike will exhaust connections.

**Finding R3 — Backup to tape, never tested**  
Last verified restore: November 2022. The DBA confirmed no restore drill has been run since.  
**Impact:** Not a migration blocker, but a risk that must be addressed. RDS automated backups + quarterly restore drill to be included in runbook.

**Finding R4 — Schema shared between web app and batch job**  
Both the web app and the batch job write to the same `transactions` table. No separate schemas, no ownership boundaries.  
**Impact:** Schema migrations require coordination across both workload teams.

---

## Cross-Workload Dependency Map

```
Web App (10.0.1.45)
    │
    ├── reads ──────────────────────► Reporting DB (10.0.1.82)  [hardcoded IP]
    │                                       ▲
    ├── writes PDFs ──► /mnt/reports/ ──────┤  [shared NFS]
    │                                       │
    └── /api/warmup ◄── cron (01:55) ───────┤
                                            │
Batch Job (cron @ 02:00)                    │
    ├── reads ──────────────────────────────┘  [hardcoded IP + plaintext creds]
    └── writes ──────► /mnt/reports/reconciled/  [shared NFS]
```

**Two couplings that a single-workload migration would miss:**
1. The batch cron pings the web app before running — migrate one without the other and batch fails silently at 02:00.
2. Both workloads share the NFS mount — removing it without coordinating both teams orphans PDF delivery and reconciliation output simultaneously.

---

## Migration Blockers (must resolve before cutover)

| ID | Workload | Finding | Resolution |
|----|----------|---------|------------|
| B-01 | Web App | Hardcoded DB IP | Replace with env var `DB_HOST`, use RDS endpoint |
| B-02 | Web App + Batch | Shared NFS mount | Migrate to S3; update both write paths |
| B-03 | Batch | Plaintext DB credentials | Move to AWS Secrets Manager before any cloud deploy |
| B-04 | Web App | Sessions on local disk | Move to ElastiCache (Redis) |
| B-05 | Batch → Web App | Cache-warm cron coupling | Decouple: move warm-up to EventBridge rule targeting ECS task directly |

## Non-Blockers (fix during migration, not before)

| ID | Workload | Finding | Resolution |
|----|----------|---------|------------|
| N-01 | Batch | No idempotency | Rewrite output logic to upsert, not append |
| N-02 | Reporting DB | No connection pooling | Add RDS Proxy |
| N-03 | Reporting DB | Backup never tested | Restore drill in go-live runbook |
| N-04 | Web App | Statics served by Flask | Move to S3 + CloudFront |
