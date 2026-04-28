# Architecture Decision Records — Index
**Project:** Contoso Financial Cloud Migration  
**Team:** TimisA  
**Last updated:** 2026-04-28  

---

## Status delle decisioni

| ADR | Titolo | Status | Challenge |
|-----|--------|--------|-----------|
| [ADR-0001](0001-dns-over-hardcoded-ip.md) | Replace Hardcoded IPs with DNS Endpoints | ✅ Accepted | Discovery |
| [ADR-0002](0002-separate-s3-storage-per-workload.md) | Separate S3 Buckets per Workload | ✅ Accepted | Discovery |
| [ADR-0003](0003-secrets-management.md) | Secrets Management via AWS Secrets Manager | ✅ Accepted | Discovery |
| [ADR-0004](0004-session-state-elasticache.md) | Session State → ElastiCache Redis | ✅ Accepted | Discovery |
| [ADR-0005](0005-decouple-batch-webapp-dependency.md) | Decouple Batch/WebApp Cron Dependency | ✅ Accepted | Discovery |
| [ADR-0006](0006-compute-target-ecs-fargate-aws-batch.md) | Compute: ECS Fargate + AWS Batch | ✅ Accepted | Options |
| [ADR-0007](0007-rds-multi-az-read-replica-rds-proxy.md) | RDS Multi-AZ + Read Replica + RDS Proxy | ✅ Accepted | Options |
| [ADR-0008](0008-batch-idempotency.md) | Batch Job Idempotency | ✅ Accepted | Options |

---

## Architettura target — visione d'insieme

```
                        ┌─────────────────────────────────────────────┐
                        │                   AWS Cloud                  │
                        │                                              │
  Users ──► CloudFront ──► ALB ──► ECS Fargate (Web App)             │
                        │              │         │         │           │
                        │         ElastiCache  S3 Reports  Secrets Mgr│
                        │          (Sessions)  (ADR-0002)  (ADR-0003) │
                        │              │                               │
                        │         RDS Proxy ──► RDS Primary (Multi-AZ)│
                        │                           │                  │
                        │                      Read Replica            │
                        │                           ▲                  │
  EventBridge ──────────┼──► AWS Batch Job          │                  │
  (02:00 UTC)           │        │         ─────────┘                  │
                        │    S3 Batch Output  (5 internal teams)       │
                        │   (ADR-0002)                                 │
                        └─────────────────────────────────────────────┘
```

---

## Blockers risolti

| Blocker | Finding | ADR che lo risolve |
|---------|---------|-------------------|
| IP hardcodato in codice | W1-1, B4 | ADR-0001 |
| Mount NFS condiviso | W1-2, B2 | ADR-0002 |
| Credenziali in chiaro | B4 | ADR-0003 |
| Sessioni su disco locale | W1-3 | ADR-0004 |
| Cron batch→webapp hardcodato | B1 | ADR-0005 |

---

## Decisioni chiave per CTO e CFO

**Per il CTO — ogni scelta è cloud-native:**
- Nessun EC2 statico: ECS Fargate e AWS Batch eliminano il provisioning manuale
- La read replica risolve un problema di produzione già esistente (query analitiche che bloccano le scritture)
- EventBridge sostituisce cron — dipendenze cross-workload ora visibili e monitorabili

**Per il CFO — ogni costo extra è giustificato:**
- ElastiCache (~€50/mese): elimina il refactor sessioni post-migrazione
- Read replica (~€180/mese): risolve i timeout della web app durante business hours
- Secrets Manager (~€5/mese): elimina il rischio di credential breach da password 7 anni senza rotazione
- RDS Proxy (~€30/mese): previene connection exhaustion al primo spike di carico

**Costo aggiuntivo totale ADR:** ~€265/mese — già contabilizzato nell'analisi costi/tempi/benefici che mostra €19.500 di risparmio netto a 24 mesi.

---

## Regola sulle ADR

Le ADR sono immutabili dopo l'approvazione. Se una decisione cambia, si apre una nuova ADR che sopersede la precedente — non si modifica quella esistente. Questo garantisce una traccia completa di come e perché l'architettura è evoluta.
