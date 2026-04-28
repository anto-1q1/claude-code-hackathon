# Team TimisA

## Participants
- Antonella Timis (PM · Architect · Dev · Platform · Quality)

## Scenario
Scenario 2: Cloud Migration — "The Lift, the Shift, and the 4am Call"

## What We Built
_Da completare man mano che avanziamo._

Contoso Financial ha tre workload on-prem da migrare su AWS: una web app customer-facing, un batch job notturno di riconciliazione, e un reporting database interrogato da 5 team interni. Abbiamo prodotto artefatti cloud-ready che girano in locale via Docker Compose, con stand-in che mappano esattamente ai primitivi AWS reali.

La decisione strategica — refactor cloud-native diretto invece di lift-and-shift — è supportata da un'analisi costi/tempi/benefici che dimostra un risparmio netto di €19.500 su 24 mesi con un delta temporale di sole 2 settimane rispetto al lift-and-shift.

## Challenges Attempted

| # | Challenge | Status | Notes |
|---|-----------|--------|-------|
| 1 | The Memo | in progress | Analisi costi/tempi completata, memo in stesura |
| 2 | The Discovery | todo | |
| 3 | The Options + ADR | todo | |
| 4 | The Container | todo | |
| 5 | The Foundation | todo | |
| 6 | The Proof | todo | |
| 7 | The Scorecard | todo | |
| 8 | The Undo | todo | |
| 9 | The Survey | todo | |

## Key Decisions
- **Refactor vs Lift-and-Shift:** scelto refactor diretto — vedi `docs/analisi-costi-tempi-benefici.md` e `docs/adr/0001-migration-pattern.md`
- **Cloud target:** AWS
- **Parallelizzazione per workload:** 3 stream indipendenti per comprimere la timeline

## How to Run It
_Da completare dopo Challenge #4 e #5._

```bash
# Prerequisiti: Docker, Docker Compose
docker compose up
```

## If We Had More Time
_Da completare a fine sessione._

## How We Used Claude Code
_Da completare a fine sessione._
