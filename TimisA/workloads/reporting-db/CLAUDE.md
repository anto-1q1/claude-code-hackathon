# CLAUDE.md — Reporting Database

## Descrizione workload

Database PostgreSQL interrogato direttamente da 5 team interni con query analitiche. Attualmente on-prem, accesso diretto via IP.

## Target AWS

- **DB:** RDS PostgreSQL Multi-AZ (Postgres in locale)
- **Accesso:** tramite VPC privata, mai esposto su internet
- **Read replicas:** almeno una, per isolare i carichi analitici dalla scrittura
- **Backup:** RDS automated backup, retention 7 giorni

## Dipendenze note (da verificare in Discovery)

- 5 team accedono con credenziali diverse (da migrare su IAM auth o Secrets Manager)
- Accesso probabilmente hardcodato su IP on-prem — da risolvere con endpoint DNS
- Query analitiche pesanti: valutare read replica dedicata

## Regole specifiche

- Nessun accesso pubblico (`publicly_accessible = false` in Terraform)
- Le connection string non compaiono mai in chiaro nel codice IaC
- Le migrazioni schema vanno versionate (es. con Flyway o Liquibase)
- Prima del cutover: validare che tutte le query dei 5 team funzionino sulla read replica
