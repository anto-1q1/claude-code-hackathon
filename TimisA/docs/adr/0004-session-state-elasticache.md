# ADR-0004 — Move Session State from Local Disk to ElastiCache (Redis)

**Status:** Accepted  
**Date:** 2026-04-28  
**Deciders:** Team TimisA  

---

## Context

Discovery (Finding W1-3) found that Flask sessions are stored on local disk at `/tmp/flask_sessions/` on the web app VM.

This makes the web app stateful: a user's session is tied to a specific VM instance. In a containerized environment on ECS Fargate:
- Containers are ephemeral — they can be stopped and replaced at any time
- With auto-scaling, multiple container instances run in parallel
- A request hitting a different container than the one that created the session will find no session data — the user is logged out

Horizontal scaling is impossible until sessions are externalized.

---

## Decision

Move Flask session storage to **ElastiCache Redis** (Redis in local Docker Compose).

```python
# Flask config
from flask_session import Session
import redis

app.config["SESSION_TYPE"] = "redis"
app.config["SESSION_REDIS"] = redis.from_url(os.environ["REDIS_URL"])
Session(app)
```

**Environment variable:**
```bash
# Local
REDIS_URL=redis://redis:6379

# Cloud
REDIS_URL=redis://contoso-webapp-cache.xyz.cache.amazonaws.com:6379
```

**Session TTL:** 8 hours (matches current business session length).  
**Encryption:** ElastiCache encryption at rest and in transit enabled.

---

## Consequences

**Positive:**
- Web app becomes fully stateless — any number of containers can serve any request
- ECS Fargate auto-scaling now works correctly
- Container restarts and deployments are transparent to logged-in users
- Redis session store is faster than disk I/O

**Negative:**
- ElastiCache adds ~€50/month (cache.t3.micro) — acceptable
- Redis becomes a dependency: if ElastiCache is unavailable, sessions are unavailable. Mitigated by ElastiCache Multi-AZ with automatic failover.

---

## Implementation Checklist

- [ ] Add `flask-session` and `redis` to `requirements.txt`
- [ ] Update Flask app config to use Redis session store
- [ ] Add `REDIS_URL` environment variable to ECS Task Definition
- [ ] Add Redis service to `docker-compose.yml` with healthcheck
- [ ] Remove `/tmp/flask_sessions/` references from codebase
- [ ] Set session TTL to 8 hours
- [ ] Enable ElastiCache encryption at rest and in transit
