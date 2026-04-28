"""
Discovery regression — Finding B1: cache-warm cron dependency decoupled.

On-prem: a cron job hit http://10.0.1.45/api/warmup 5 minutes before the batch ran.
The batch job silently failed if the web app was down or restarting.

Fix (ADR-0005): EventBridge triggers the warmup as an ECS task; the warmup sets a
Redis key directly. The batch job is no longer coupled to web app availability.

These tests verify:
1. /api/warmup endpoint exists and is callable (not cron-dependent)
2. Calling it sets the expected Redis key (proof the cache actually warms)
3. No hardcoded IP of the web app in the batch source code
"""
import re
import os
import pytest


def _abs(relative_path):
    return os.path.join(os.path.dirname(__file__), relative_path)


def test_warmup_endpoint_callable(http, webapp_url):
    """/api/warmup is reachable via HTTP (not hidden behind cron timing)."""
    r = http.get(f"{webapp_url}/api/warmup")
    assert r.status_code == 200, (
        f"/api/warmup returned {r.status_code} — endpoint must be callable on demand, "
        "not only from cron (ADR-0005)"
    )


def test_warmup_sets_redis_key(http, webapp_url, redis_client):
    """Calling /api/warmup sets 'portfolio_cache_warmed' in Redis.

    Proves the warmup writes to the shared cache store, not to local disk or memory.
    In cloud this key is visible to all ECS tasks — horizontal scaling safe.
    """
    # Clear key before test
    redis_client.delete("portfolio_cache_warmed")

    http.get(f"{webapp_url}/api/warmup")

    value = redis_client.get("portfolio_cache_warmed")
    assert value is not None, (
        "'portfolio_cache_warmed' key not found in Redis after /api/warmup call. "
        "Warmup must write to Redis (shared cache), not in-process memory."
    )
    assert value == b"1", f"Unexpected value: {value}"


def test_batch_source_no_webapp_ip():
    """reconcile.py contains no hardcoded web app IP (Finding B1 — 10.0.1.45)."""
    with open(_abs("../workloads/batch/reconcile.py")) as f:
        code = f.read()
    assert "10.0.1.45" not in code, (
        "Web app IP 10.0.1.45 still present in reconcile.py — "
        "cache-warm coupling not removed (ADR-0005)"
    )


def test_batch_source_no_curl_warmup():
    """reconcile.py contains no curl/requests call to /api/warmup (cron pattern removed)."""
    with open(_abs("../workloads/batch/reconcile.py")) as f:
        code = f.read()
    assert "warmup" not in code.lower(), (
        "warmup reference found in reconcile.py — batch job must not trigger warmup itself. "
        "Warmup is handled by EventBridge (ADR-0005)."
    )
    assert "curl" not in code.lower(), (
        "curl call found in reconcile.py — batch must not shell out to trigger warmup"
    )
