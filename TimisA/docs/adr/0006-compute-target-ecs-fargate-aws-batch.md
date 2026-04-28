# ADR-0006 — Compute Target: ECS Fargate (Web App) + AWS Batch (Batch Job)

**Status:** Accepted  
**Date:** 2026-04-28  
**Deciders:** Team TimisA  

---

## Context

We need to choose the compute target on AWS for the two active workloads: the customer-facing web app and the nightly reconciliation batch job. The reporting database is covered separately (ADR-0007).

---

## Decision

| Workload | Compute Target | Reason |
|----------|---------------|--------|
| Web App | **ECS Fargate** | Containerized, HTTP traffic, needs auto-scaling |
| Batch Job | **AWS Batch** | Scheduled, variable duration, pay-per-execution |

---

## Web App — ECS Fargate

**Why Fargate over EC2:**
Fargate is serverless containers — no EC2 instances to patch, size, or manage. The web app is a good fit: it's stateless (after ADR-0004), it needs horizontal scaling during business hours, and it has no special hardware requirements.

**Why ECS over EKS:**
EKS (Kubernetes) adds significant operational overhead for a single-service web app. ECS is simpler, cheaper to operate, and sufficient for this workload. EKS would be reconsidered if the number of services grows beyond 5–6.

**Architecture:**
```
CloudFront → ALB → ECS Fargate (2–6 tasks, auto-scaling on CPU 60%)
                        └── ElastiCache Redis (sessions)
                        └── RDS PostgreSQL (read replica for portfolio data)
                        └── S3 (PDF report writes)
                        └── Secrets Manager (DB credentials)
```

**Scaling policy:** target tracking on CPU utilization, 60% threshold, min 2 tasks, max 6 tasks.

---

## Batch Job — AWS Batch

**Why AWS Batch over Lambda:**
The reconciliation job runs for up to 2–3 hours and processes large datasets. Lambda has a 15-minute execution limit and memory constraints that make it unsuitable. AWS Batch is designed for exactly this workload: long-running, compute-intensive, scheduled jobs.

**Why AWS Batch over EC2 scheduled task:**
EC2 would require a always-on instance waiting for the 02:00 cron. AWS Batch provisions compute only when the job runs and terminates it after — the job currently runs ~2 hours/night, meaning an EC2 would be idle 22 hours/day. AWS Batch eliminates that waste entirely.

**Architecture:**
```
EventBridge (02:00 UTC) → AWS Batch Job
                              └── RDS PostgreSQL (transactions read)
                              └── S3 contoso-batch-output-prod (output write)
                              └── Secrets Manager (DB credentials)
                              └── SNS (completion/failure notification)
```

---

## Alternatives Rejected

| Option | Rejected because |
|--------|-----------------|
| EC2 for web app | Manual scaling, patching overhead, no container benefits |
| EKS for web app | Operational overhead disproportionate to a single service |
| Lambda for batch | 15-min execution limit, memory constraints for large datasets |
| EC2 for batch | Pays for 22 hours of idle compute every night |
| App Runner | Less control over networking and VPC configuration needed for RDS access |

---

## Implementation Checklist

- [ ] Create ECS Cluster `contoso-webapp-cluster`
- [ ] Create ECS Task Definition `contoso-webapp` (from Dockerfile, Challenge #4)
- [ ] Create ECS Service with ALB and auto-scaling policy
- [ ] Create AWS Batch Compute Environment `contoso-batch-env` (Fargate)
- [ ] Create AWS Batch Job Definition `contoso-reconciliation-job`
- [ ] Create AWS Batch Job Queue `contoso-batch-queue`
- [ ] Wire EventBridge rules (ADR-0005) to ECS Task and Batch Job
