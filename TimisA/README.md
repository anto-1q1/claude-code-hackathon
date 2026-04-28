# Team TimisA

## Participants
- Antonella Timis (PM · Architect · Dev · Platform · Quality)
- Andrea Curcio (Dev · Platform · Infrastructure · Quality)

## Scenario
Scenario 2: Cloud Migration — "The Lift, the Shift, and the 4am Call"

## What We Built

Contoso Financial ha tre workload on-prem da migrare su AWS: una web app customer-facing, un batch job notturno di riconciliazione, e un reporting database interrogato da 5 team interni.

Abbiamo prodotto artefatti cloud-ready che girano in locale via Docker Compose, con stand-in che mappano esattamente ai primitivi AWS reali (MinIO→S3, PostgreSQL→RDS, Redis→ElastiCache).

La decisione strategica — **refactor cloud-native diretto invece di lift-and-shift** — è supportata da un'analisi costi/tempi/benefici che dimostra un risparmio netto di **€19.500 su 24 mesi** con un delta temporale di sole 2 settimane.

La discovery ha portato alla luce **5 blocker critici**, inclusa una dipendenza batch→webapp silenziosa sconosciuta al team di sviluppo, e credenziali DB in chiaro nel codice da 7 anni. Tutti e 5 risolti prima della containerizzazione.

## Challenges Attempted

| # | Challenge | Status | Notes |
|---|-----------|--------|-------|
| 1 | The Memo | ✅ Complete | Analisi costi/tempi/benefici + decisione strategica in `docs/memo.md` |
| 2 | The Discovery | ✅ Complete | 5 blocker identificati, dipendenza nascosta surfaced — `docs/discovery.md` |
| 3 | The Options + ADR | ✅ Complete | 8 ADR accettati in `docs/adr/` — ogni scelta architetturale documentata |
| 4 | The Container | ✅ Complete | Dockerfile per webapp, batch, reporting-db + docker-compose.yml |
| 5 | The Foundation | ✅ Complete | Terraform IaC con 7 moduli (networking, webapp, batch, database, cache, storage, secrets) |
| 6 | The Proof | ✅ Complete | Test suite 3 livelli: smoke, contract, discovery + data integrity |
| 7 | The Scorecard | ✅ Complete | Eval harness IaC — golden patterns vs bad patterns in `scorecard/` |
| 8 | The Undo | ⏳ Scheduled | Git history scrub pianificato W1 Giorno 1 — credenziale `C0nt0s0#2019` in ADR-0003 |
| 9 | The Survey | todo | |

## Key Decisions

- **Refactor vs Lift-and-Shift:** refactor diretto — risparmio €19.500 su 24 mesi, nessun secondo progetto. Vedi `docs/analisi-costi-tempi-benefici.md` e `docs/memo.md`
- **Compute:** ECS Fargate per la web app (stateless, autoscaling 2–6 task), AWS Batch per il batch job (pay-per-execution, evita 22h di idle EC2/notte)
- **Sessioni:** migrate da `/tmp/flask_sessions/` a ElastiCache Redis — prerequisito per Fargate autoscaling
- **Secrets:** AWS Secrets Manager con rotazione automatica 6 mesi — rimossi dal codice e dalla pipeline CI
- **Database:** RDS Multi-AZ + read replica + RDS Proxy — risolve write blocking, connection limit e backup non verificati dal 2022
- **Decoupling:** dipendenza batch→webapp rimossa via EventBridge + ECS Task standalone

## How to Run It

```bash
# Prerequisiti: Docker, Docker Compose
cd TimisA
docker compose up

# Verifica che tutti i servizi siano healthy
docker compose ps

# Esegui la test suite completa
cd tests && bash run_tests.sh
```

## If We Had More Time

- **Challenge #8 (The Undo):** completare il git history scrub per rimuovere la credenziale `C0nt0s0#2019` dalla history di ADR-0003
- **Challenge #7 (The Scorecard):** eval harness su IaC output di Claude — golden set di pattern corretti vs pattern da bloccare
- **Challenge #9 (The Survey):** retrospettiva sull'uso di Claude Code nel progetto
- **Monitoring runbook:** CloudWatch alarms + SNS per il batch job (condizione CTO per go-live)
- **Blue/green deployment:** procedura di cutover documentata con rollback plan

## How We Used Claude Code

Claude Code ha accompagnato ogni fase del progetto come collaboratore tecnico attivo:

- **Discovery:** analisi del codebase on-prem, identificazione dei 5 blocker e della dipendenza batch→webapp nascosta
- **ADR:** generazione e revisione degli 8 Architecture Decision Records — ogni trade-off discusso e documentato
- **Strategia:** analisi costi/tempi/benefici lift-and-shift vs refactor, con numeri reali a supporto della raccomandazione
- **CLAUDE.md e hooks:** configurazione dei guardrail (PreToolUse hook che blocca segreti in chiaro nei file `.tf` e `.env`)
- **Simulazione stakeholder:** preparazione e simulazione del meeting con CFO e CTO per anticipare e rispondere alle obiezioni
- **Presentazione:** generazione del deck HTML (`presentation.html`) con 12 slide pronte per la live demo
