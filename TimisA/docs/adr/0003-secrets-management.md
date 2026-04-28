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

**Rotation:** automatic rotation enabled on all DB credentials, **6-month cycle** via Secrets Manager + RDS native integration. Rotation is automatic and transparent — no manual intervention, no downtime.

**Password masking:** credentials retrieved from Secrets Manager are never logged, printed, or exposed in ECS Task Definition outputs, CloudWatch logs, or debug output. Any logging of connection objects must explicitly exclude the password field:
```python
# Never log credentials
logger.info(f"Connecting to DB at {os.environ['DB_HOST']}")  # OK
logger.info(f"Connection string: {conn_string}")              # NEVER
```
CloudWatch log groups for all workloads have a log filter that redacts any string matching password patterns before storage.

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
- [ ] Enable automatic rotation on both secrets with 6-month cycle
- [ ] Add `.env` to `.gitignore`, commit `.env.example`
- [ ] Implement `PreToolUse` hook in `.claude/hooks/` to block plaintext secrets in IaC
- [ ] Add CloudWatch log filter to redact password patterns across all log groups
- [ ] Audit all logging statements in web app and batch job — remove any that expose credentials
- [ ] Verify git history does not contain the exposed password (git history scrub if needed)
