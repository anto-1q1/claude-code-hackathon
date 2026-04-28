# CLAUDE.md — Web App (Customer-Facing)

## Descrizione workload

Applicazione web esposta al pubblico. Serve clienti retail di Contoso Financial.

## Target AWS

- **Compute:** ECS Fargate (container, no server da gestire)
- **Load balancer:** ALB
- **CDN:** CloudFront
- **Storage statico:** S3
- **Secrets:** AWS Secrets Manager

## Regole specifiche

- Build multi-stage: stage `builder` separato dallo stage finale
- Utente non-root nel container (`USER appuser`)
- Health check obbligatorio su `/health`
- La stessa immagine deve funzionare in locale (docker compose) e in cloud con solo una variabile d'ambiente `ENV` che cambia
- Nessuna logica di business nel layer di presentazione
