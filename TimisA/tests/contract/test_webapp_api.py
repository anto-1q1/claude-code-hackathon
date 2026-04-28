"""Contract: webapp API response schemas and headers."""
import time
import pytest


HEALTH_REQUIRED_KEYS = {"status", "env", "checks", "timestamp"}
HEALTH_CHECK_KEYS    = {"db", "redis"}


def test_health_schema_complete(http, webapp_url):
    """/health response contains all required fields."""
    body = http.get(f"{webapp_url}/health").json()
    missing = HEALTH_REQUIRED_KEYS - body.keys()
    assert not missing, f"/health missing keys: {missing}"


def test_health_checks_schema(http, webapp_url):
    """/health.checks contains db and redis sub-checks."""
    checks = http.get(f"{webapp_url}/health").json().get("checks", {})
    missing = HEALTH_CHECK_KEYS - checks.keys()
    assert not missing, f"/health.checks missing: {missing}"


def test_health_checks_all_ok(http, webapp_url):
    """All individual health checks report 'ok'."""
    checks = http.get(f"{webapp_url}/health").json().get("checks", {})
    failed = {k: v for k, v in checks.items() if v != "ok"}
    assert not failed, f"Degraded checks: {failed}"


def test_health_timestamp_recent(http, webapp_url):
    """/health timestamp is within 5 seconds of now (server clock in sync)."""
    body = http.get(f"{webapp_url}/health").json()
    delta = abs(time.time() - body["timestamp"])
    assert delta < 5, f"Timestamp drift too large: {delta:.1f}s"


def test_warmup_endpoint_schema(http, webapp_url):
    """/api/warmup returns {warmed: true}."""
    r = http.get(f"{webapp_url}/api/warmup")
    assert r.status_code == 200
    body = r.json()
    assert body.get("warmed") is True, f"Unexpected response: {body}"


def test_no_server_header_leaks(http, webapp_url):
    """Response headers do not expose server stack details."""
    headers = http.get(f"{webapp_url}/health").headers
    server = headers.get("Server", "")
    assert "werkzeug" not in server.lower(), (
        "Server header exposes Werkzeug dev server — gunicorn must be used"
    )
