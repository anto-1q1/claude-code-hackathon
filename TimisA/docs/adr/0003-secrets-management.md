# ADR-0003 — Secrets Management via AWS Secrets Manager

**Status:** Accepted  
**Date:** 2026-04-28  
**Deciders:** Team TimisA  

---

## Context

Discovery (Finding B4) found plaintext DB credentials hardcoded in `reconcile.py`:

```python
conn = psycopg2.connect("host=10.0.1.82 user=batch_user password=C0nt0s0#2019")
```

Password unchanged for 7 years. No rotation policy. Credential visible to anyone with read access to the codebase.

This is a security blocker — no cloud deployment proceeds until this is resolved.

---

## Decision

All credentials (DB passwords, API keys, service tokens) are stored in **AWS Secrets Manager** and never written in plaintext to code, config files, `.env` files, or IaC.

**Access pattern:**
```python
import boto3, json

def get_secret(secret_name):
    client = boto3.client("secretsmanager", region_name="eu-west-1")
    return json.loads(client.get_secret_value(SecretId=secret_name)["SecretString"])

creds = get_secret("contoso/batch/db-credentials")
conn = psycopg2.connect(host=os.environ["DB_HOST"], user=creds["username"], password=creds["password"])
```

**Rotation:** automatic rotation enabled on all DB credentials, 30-day cycle via Secrets Manager + RDS integration.

**Local (Docker Compose):** credentials injected via `.env` file that is git-ignored. A `.env.example` with placeholder values is committed instead.

**Guardrail:** a `PreToolUse` hook blocks any Claude edit that writes a string matching a password/secret pattern into `.tf`, `.py`, `.env`, or `.ini` files. See `CLAUDE.md`.

---

## Consequences

**Positive:**
- Credentials never in git history, ever
- Automatic rotation eliminates the "unchanged for 7 years" risk
- Audit trail: every secret access is logged in CloudTrail
- Single source of truth — no credential drift across environments

**Negative:**
- Secrets Manager costs ~$0.40/secret/month — negligible
- Code must handle transient Secrets Manager API failures (retry with backoff)

---

## Implementation Checklist

- [ ] Remove plaintext credentials from `reconcile.py`
- [ ] Create secrets in Secrets Manager: `contoso/batch/db-credentials`, `contoso/webapp/db-credentials`
- [ ] Enable automatic rotation on both secrets
- [ ] Add `.env` to `.gitignore`, commit `.env.example`
- [ ] Implement `PreToolUse` hook in `.claude/hooks/` to block plaintext secrets in IaC
- [ ] Verify git history does not contain the exposed password (git history scrub if needed)
