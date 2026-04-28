# CLAUDE.md — Batch Job (Riconciliazione Notturna)

## Descrizione workload

Job schedulato che gira ogni notte. Legge transazioni dal DB, le riconcilia con i sistemi esterni, scrive l'esito su S3.

## Target AWS

- **Compute:** AWS Batch oppure ECS Task schedulato via EventBridge
- **Storage output:** S3 (MinIO in locale)
- **DB sorgente:** RDS PostgreSQL (Postgres in locale)
- **Notifiche esito:** SNS

## Regole specifiche

- Il job deve essere idempotente: se rieseguito sulla stessa finestra temporale, non duplica dati
- Timeout massimo: 4 ore (oltre va in errore e notifica)
- I log vanno su CloudWatch (stdout in locale va bene)
- Nessuna dipendenza da filesystem condiviso — tutto passa da S3 o DB
- Le credenziali DB arrivano solo da variabili d'ambiente, mai hardcoded
