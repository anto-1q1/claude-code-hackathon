# ADR-0005 — Decouple Batch Job / Web App Cache-Warm Dependency

**Status:** Accepted  
**Date:** 2026-04-28  
**Deciders:** Team TimisA  

---

## Context

Discovery (Finding B1) revealed an undocumented cross-workload dependency:

```cron
55 01 * * * curl -s http://10.0.1.45/api/warmup > /dev/null
```

The batch job hits the web app's `/api/warmup` endpoint 5 minutes before running to pre-load portfolio data into the web app's in-memory cache. This was introduced after a batch failure in 2023 caused by cold-cache response times — but never documented.

This coupling creates three problems in cloud:
1. The web app IP `10.0.1.45` is hardcoded in the cron — breaks immediately post-migration
2. If the web app is restarting or scaling during the cron window, the warm-up silently fails and the batch job runs with cold cache
3. Two independently-deployed workloads are now operationally coupled — a web app deployment window can break the nightly batch

---

## Decision

Remove the cron-based warm-up entirely. Replace with an **EventBridge scheduled rule** that triggers a dedicated ECS Task (a lightweight warm-up task, not the full web app) 5 minutes before the batch job runs.

```
EventBridge Rule (01:55 UTC)
    └── triggers ECS Task: contoso-webapp-warmup
            └── calls internal cache warm-up logic directly
                    (no HTTP, no dependency on web app availability)

EventBridge Rule (02:00 UTC)
    └── triggers AWS Batch Job: contoso-batch-reconciliation
```

The warm-up logic is extracted from the web app into a standalone function that populates ElastiCache directly — it does not depend on the web app being up.

**Why EventBridge instead of keeping the cron:**
- EventBridge is the cloud-native scheduler — no VM required, no cron syntax, full audit trail in CloudTrail
- The two rules are visibly coupled in the same EventBridge rule group, making the dependency explicit and documented
- Failure of the warm-up task triggers an SNS alert before the batch runs — ops can intervene rather than discovering a slow batch at 06:00

---

## Consequences

**Positive:**
- Web app and batch job can be deployed, restarted, and scaled independently
- The dependency is now explicit, documented, and observable
- Warm-up failure is alertable before batch starts — not discovered after
- Eliminates the hardcoded IP in the cron

**Negative:**
- Warm-up logic must be extracted into a standalone module — small refactor effort
- Two EventBridge rules to maintain instead of one cron line

---

## Implementation Checklist

- [ ] Extract `/api/warmup` logic into `services/cache_warmer.py` (shared module)
- [ ] Create ECS Task Definition `contoso-webapp-warmup` that runs `cache_warmer.py`
- [ ] Create EventBridge rule `contoso-warmup-trigger` at 01:55 UTC → ECS Task
- [ ] Create EventBridge rule `contoso-batch-trigger` at 02:00 UTC → AWS Batch Job
- [ ] Add SNS alert on warm-up task failure
- [ ] Remove cron entry from batch job VM
- [ ] Remove `/api/warmup` endpoint from web app (or keep as internal-only with auth)
