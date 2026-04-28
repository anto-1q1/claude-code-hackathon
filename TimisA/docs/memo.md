# Migration Decision Memo
**To:** CFO, Legal, CTO, SRE Lead  
**From:** Team TimisA  
**Date:** 2026-04-28  
**Subject:** Cloud Migration Pattern — Recommendation: Refactor Cloud-Native Direct  

---

## Decision

We recommend **refactor cloud-native directly**, not lift-and-shift followed by a second optimization project. This memo explains why lift-and-shift costs more, not less, and names the risks we are accepting.

---

## The Case Against Lift-and-Shift

Lift-and-shift is not a cheaper option. It is a deferred cost with interest.

The CFO signed the cloud contract expecting savings. Those savings do not materialize on EC2 instances running the same over-provisioned on-prem configuration — they materialize when workloads use cloud primitives correctly: auto-scaling compute, managed batch execution, read replicas for analytical load. Lift-and-shift delivers none of that.

More critically: the CTO has stated explicitly that lift-and-shift is not the destination. That means a second migration project is not hypothetical — it is scheduled the moment we go live. We would be paying for the same migration twice, the second time under worse conditions: production traffic live on cloud, accumulated cloud-specific technical debt, and an ops team managing infrastructure that was never designed for where it is running.

---

## The Numbers

| | Lift-and-Shift | Refactor Direct |
|--|--|--|
| One-time migration cost | ~€18,000 | ~€30,000 |
| Monthly cloud ops cost | ~€760/month | ~€495/month |
| Cost of inevitable second refactor | ~€25,000 | — |
| **Total at 24 months** | **~€61,400** | **~€41,900** |

**Net saving at 24 months: ~€19,500 in favour of refactor.**

Timeline difference with three parallel workload streams: **2 weeks**. Not months. Two weeks.

---

## What We Are Accepting

**Risk 1 — Timeline.** Refactor takes 8–9 weeks vs 6–7 for lift-and-shift with parallel streams. We accept this. Two weeks is not a business-critical delay; a failed second migration 18 months from now is.

**Risk 2 — Team upskilling.** ECS Fargate and AWS Batch require ramp-up. We mitigate this with targeted training in weeks 1–2, per-workload `CLAUDE.md` files that encode conventions for every engineer touching the codebase, and a local Docker Compose environment that mirrors production exactly.

**Risk 3 — Coordination complexity.** Three parallel streams require active coordination. We mitigate this with weekly cross-stream checkpoints and explicit interface contracts between workloads before development starts.

---

## What We Are Not Accepting

We are not accepting a lift-and-shift that the CTO will reverse within 18 months. We are not accepting cloud costs that exceed on-prem because we replicated on-prem patterns on cloud infrastructure. We are not accepting an architecture that leaves the SRE team managing manually-scaled EC2 instances and single-AZ databases at 4am.

---

## Recommendation

Proceed with refactor cloud-native direct. Three parallel streams, one per workload. Target go-live in 9 weeks. Full architecture detail and service-level decisions in `docs/adr/`.

This is the cheaper option. It is also the right one.
