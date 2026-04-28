# CLAUDE.md — Team TimisA
## Scenario 2: Cloud Migration — Contoso Financial

### Progetto

Contoso Financial migra tre workload on-prem su AWS. Gli artefatti girano in locale via Docker Compose con stand-in cloud (MinIO→S3, Postgres→RDS, Redis→ElastiCache).

### I tre workload

| Workload | Cartella | Target AWS |
|----------|----------|------------|
| Web app customer-facing | `workloads/webapp/` | ECS Fargate + ALB + CloudFront |
| Batch notturno riconciliazione | `workloads/batch/` | AWS Batch + EventBridge |
| Reporting database (5 team) | `workloads/reporting-db/` | RDS PostgreSQL Multi-AZ + read replica |

### Struttura

```
TimisA/
├── CLAUDE.md                  ← questo file
├── README.md                  ← submission doc
├── presentation.html          ← deck HTML (da generare)
├── docker-compose.yml         ← orchestrazione locale
├── docs/
│   ├── memo.md                ← decisione strategica (Challenge #1)
│   ├── discovery.md           ← current state + dipendenze (Challenge #2)
│   ├── analisi-costi-tempi-benefici.md
│   └── adr/                   ← Architecture Decision Records
├── workloads/
│   ├── webapp/                ← Dockerfile, src, CLAUDE.md
│   ├── batch/                 ← script, CLAUDE.md
│   └── reporting-db/         ← schema, migrations, CLAUDE.md
├── infra/                     ← Terraform IaC (Challenge #5)
└── tests/                     ← validation suite (Challenge #6)
```

### Convenzioni globali

- Nomi risorse: `contoso-{workload}-{env}` (es. `contoso-webapp-prod`)
- Segreti: mai in chiaro — solo variabili d'ambiente o AWS Secrets Manager
- Ogni servizio in `docker-compose.yml` ha un `healthcheck`
- ADR in `docs/adr/NNNN-titolo.md`, immutabili dopo approvazione
- Un `CLAUDE.md` per workload — guida specifica per chi lavora su quella cartella

### Guardrail attivi

- Hook `PreToolUse`: blocca qualsiasi scrittura di segreti in chiaro nei file `.tf` o `.env`
- Prefer AWS Secrets Manager per credenziali DB e API key (vedi ADR-0002)

### Strategia di migrazione

Refactor cloud-native diretto (non lift-and-shift). Motivazione: con 3 stream paralleli il delta temporale è solo 2 settimane, ma risparmio stimato €19.500 su 24 mesi evitando il secondo progetto di refactor che il lift-and-shift renderebbe inevitabile. Vedi `docs/analisi-costi-tempi-benefici.md` e `docs/memo.md`.
