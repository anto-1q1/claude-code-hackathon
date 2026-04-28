"""Smoke: webapp startup, reachability, health check."""
import pytest


def test_webapp_reachable(http, webapp_url):
    """/health returns HTTP 200."""
    r = http.get(f"{webapp_url}/health")
    assert r.status_code == 200, f"Expected 200, got {r.status_code}: {r.text}"


def test_webapp_returns_json(http, webapp_url):
    """/health Content-Type is application/json."""
    r = http.get(f"{webapp_url}/health")
    assert "application/json" in r.headers.get("Content-Type", "")


def test_webapp_health_status_healthy(http, webapp_url):
    """/health reports status: healthy (all backing services up)."""
    r = http.get(f"{webapp_url}/health")
    body = r.json()
    assert body.get("status") == "healthy", (
        f"App degraded — checks: {body.get('checks')}"
    )


def test_webapp_root_responds(http, webapp_url):
    """Root endpoint returns 200."""
    r = http.get(f"{webapp_url}/")
    assert r.status_code == 200
