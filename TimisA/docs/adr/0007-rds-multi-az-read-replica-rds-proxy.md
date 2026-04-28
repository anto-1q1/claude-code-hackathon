# ADR-0007 — RDS PostgreSQL: Multi-AZ + Read Replica + RDS Proxy

**Status:** Accepted  
**Date:** 2026-04-28  
**Deciders:** Team TimisA  

---

## Context

Discovery (Findings R1, R2, R3) revealed three issues with the reporting database:

- **R1:** Five teams run heavy analytical queries that block write operations — web app timeouts during business hours are a direct consequence
- **R2:** No connection pooling — 47 persistent connections at peak, max_connections 100, no headroom
- **R3:** Backup to tape, last verified restore November 2022

The reporting database is the most critical and most fragile component in the current architecture. It is a single point of failure with no tested recovery path.

---

## Decision

Deploy RDS PostgreSQL with three layers of resilience:

### Layer 1 — Multi-AZ Deployment
Primary instance in `eu-west-1a`, standby in `eu-west-1b`. Automatic failover in 60–120 seconds. Transparent to the application via DNS endpoint (ADR-0001).

### Layer 2 — Read Replica
One read replica in `eu-west-1c` dedicated to analytical workloads. All five internal teams (Finance, Risk, Compliance, Executive, Ops) are routed to the read replica. Only the web app and batch job write to the primary.

```
Web App (writes)  ──► Primary RDS (eu-west-1a)
                           └── replicates to ──► Standby (eu-west-1b) [Multi-AZ]
                           └── replicates to ──► Read Replica (eu-west-1c)
                                                      ▲
Batch Job (reads/writes) ──► Primary                  │
                                                      │
5 Internal Teams (reads only) ────────────────────────┘
```

This directly resolves the production issue where analytical queries block writes — they now run on a completely separate instance.

### Layer 3 — RDS Proxy
RDS Proxy sits in front of the primary instance and manages connection pooling. Applications connect to RDS Proxy (which maintains a warm pool of DB connections) rather than directly to RDS.

**Why this solves R2:** current peak is 47 connections out of 100. With RDS Proxy, applications open connections to the proxy (which can handle thousands), and the proxy multiplexes them into a small pool to RDS. The 100-connection limit effectively disappears.

---

## Instance Sizing

| Instance | Type | Notes |
|----------|------|-------|
| Primary | `db.m5.large` | Writes from webapp + batch |
| Read Replica | `db.m5.xlarge` | Larger — handles 5 teams' analytical queries |
| RDS Proxy | Managed | Sized automatically by AWS |

---

## Backup Strategy

- RDS automated backups: enabled, 7-day retention
- Point-in-time recovery: enabled
- Quarterly restore drill: added to ops runbook — a restore is executed to a test instance every quarter and verified against a known dataset
- Tape backup: decommissioned after first successful RDS restore drill

---

## Consequences

**Positive:**
- Web app timeouts caused by analytical queries are eliminated
- Single point of failure removed — failover is automatic
- Connection exhaustion risk eliminated via RDS Proxy
- Backup has a tested recovery path for the first time

**Negative:**
- Read replica adds ~€180/month — justified by eliminating an existing production incident
- RDS Proxy adds ~€30/month
- Application teams must use the read replica endpoint for read-only queries (connection string change)

---

## Implementation Checklist

- [ ] Create RDS PostgreSQL `db.m5.large` Multi-AZ in `eu-west-1a`/`eu-west-1b`
- [ ] Create read replica `db.m5.xlarge` in `eu-west-1c`
- [ ] Create RDS Proxy in front of primary
- [ ] Update web app connection to use RDS Proxy endpoint
- [ ] Update batch job connection to use RDS Proxy endpoint
- [ ] Provide read replica endpoint to 5 internal teams
- [ ] Enable automated backups with 7-day retention
- [ ] Enable point-in-time recovery
- [ ] Add quarterly restore drill to ops runbook
- [ ] Set `publicly_accessible = false` on all RDS instances
- [ ] Enable encryption at rest (KMS)
