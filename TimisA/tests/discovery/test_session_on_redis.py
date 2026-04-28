"""
Discovery regression — Finding W1-3: Flask sessions on Redis, not local disk.

On-prem: sessions stored in /tmp/flask_sessions/ on the VM.
This makes the app stateful — horizontal scaling impossible.

Fix (ADR-0004): sessions backed by Redis (ElastiCache in cloud).
Same container can be replaced, restarted, or scaled to N replicas transparently.
"""
import os
import pytest


def _abs(relative_path):
    return os.path.join(os.path.dirname(__file__), relative_path)


def test_webapp_source_no_flask_session_disk():
    """/tmp/flask_sessions/ path not present in app.py (Finding W1-3)."""
    with open(_abs("../workloads/webapp/app.py")) as f:
        code = f.read()
    assert "/tmp/flask_sessions" not in code, (
        "Found /tmp/flask_sessions in app.py — local disk session store not removed. "
        "Sessions must use Redis (ADR-0004)."
    )
    assert "flask_sessions" not in code, (
        "Found flask_sessions reference in app.py"
    )


def test_webapp_uses_redis_url_env():
    """app.py reads REDIS_URL from environment (not hardcoded)."""
    with open(_abs("../workloads/webapp/app.py")) as f:
        code = f.read()
    assert "REDIS_URL" in code, (
        "REDIS_URL not referenced in app.py — Redis connection must be configured via env var"
    )
    assert "redis_lib.from_url" in code or "from_url" in code, (
        "Redis client not initialised via URL in app.py"
    )


def test_redis_available_for_sessions(redis_client):
    """Redis is reachable from the test runner (same network as webapp).

    If this fails, the webapp cannot store sessions — all users would lose
    their session on every container restart or scale event.
    """
    assert redis_client.ping(), "Redis not reachable — sessions would fail at runtime"


def test_redis_session_key_ttl(redis_client, http, webapp_url):
    """After warmup, Redis key has a TTL set (sessions are not permanent).

    Validates that keys are configured to expire — preventing unbounded Redis growth.
    """
    http.get(f"{webapp_url}/api/warmup")
    ttl = redis_client.ttl("portfolio_cache_warmed")
    # TTL > 0 means an expiry is set; -1 means no expiry (bad); -2 means key missing
    assert ttl > 0, (
        f"Redis key 'portfolio_cache_warmed' has TTL={ttl}. "
        "Keys must have an expiry set to prevent unbounded memory growth."
    )


def test_webapp_health_includes_redis_check(http, webapp_url):
    """/health endpoint reports Redis status — proves app monitors its session store."""
    body = http.get(f"{webapp_url}/health").json()
    checks = body.get("checks", {})
    assert "redis" in checks, (
        "/health does not include a Redis check. "
        "The session store must be monitored so degradation is visible."
    )
    assert checks["redis"] == "ok", (
        f"Redis check in /health is not 'ok': {checks['redis']}"
    )
