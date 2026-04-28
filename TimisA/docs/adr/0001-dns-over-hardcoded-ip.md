# ADR-0001 — Replace Hardcoded IPs with DNS Endpoints

**Status:** Accepted  
**Date:** 2026-04-28  
**Deciders:** Team TimisA  

---

## Context

Discovery (Finding W1-1, B4) revealed that both the web app (`config/production.ini`) and the batch job (`reconcile.py`) reference the reporting database via hardcoded IP `10.0.1.82`.

This pattern was tolerated on-prem where IPs were static and manually managed. It is incompatible with cloud infrastructure for two reasons:

1. **RDS does not guarantee a stable IP.** The IP of an RDS instance can change on restart, maintenance window, or instance replacement.
2. **RDS Multi-AZ failover works via DNS.** During a failover event, AWS updates the DNS endpoint to point to the standby replica within 60–120 seconds. Applications using IPs will not benefit from this — they will simply fail until manually updated.

---

## Decision

Replace all hardcoded IP references with environment variable `DB_HOST`, populated at runtime with the RDS DNS endpoint.

**Pattern to apply across all workloads:**

```bash
# Environment variable (never hardcoded)
DB_HOST=contoso-reporting-db.cluster-xyz.eu-west-1.rds.amazonaws.com
```

```python
# web app and batch job
import os
DB_HOST = os.environ["DB_HOST"]  # fails fast if not set — intentional
```

The variable is injected via:
- **Local (Docker Compose):** `environment` block in `docker-compose.yml`
- **Cloud (ECS / AWS Batch):** ECS Task Definition environment variables, sourced from AWS Secrets Manager

`DB_HOST` is never written to any config file, `.env` file committed to git, or IaC file in plaintext.

---

## Consequences

**Positive:**
- RDS Multi-AZ failover is transparent to the application
- No manual intervention required during instance replacement or maintenance
- Same codebase runs locally (Postgres container) and in cloud (RDS) with a single variable swap
- Eliminates a class of "works on my machine" failures caused by network topology differences

**Negative:**
- Developers must ensure `DB_HOST` is set in their local environment — app fails fast if missing (this is intentional: silent misconfiguration is worse than a loud startup failure)

---

## Implementation Checklist

- [ ] `config/production.ini` — remove `DB_HOST=10.0.1.82`, read from env
- [ ] `reconcile.py` line 12 — replace connection string with `os.environ["DB_HOST"]`
- [ ] `docker-compose.yml` — add `DB_HOST=postgres` for local Postgres container
- [ ] ECS Task Definition — add `DB_HOST` sourced from Secrets Manager
- [ ] AWS Batch Job Definition — same
- [ ] Verify no other IP references remain (`grep -r "10.0.1" .`)

---

## Alternatives Considered

**Keep IP, manage via `/etc/hosts`** — rejected. Requires manual maintenance on every host, breaks immediately in ECS/Fargate where we have no control over the container's hosts file.

**Use AWS PrivateLink with static IP** — rejected. Adds cost and complexity for a problem that DNS already solves natively.
