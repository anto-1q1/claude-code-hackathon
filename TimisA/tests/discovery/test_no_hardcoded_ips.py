"""
Discovery regression — Finding W1-1, B4: no hardcoded IPs.

On-prem both the web app and batch job referenced the DB via hardcoded IP 10.0.1.82.
These tests verify that IP addresses no longer appear in source code or runtime config.
"""
import os
import re
import pytest
from conftest import DB_HOST


PRIVATE_IP_PATTERN = re.compile(
    r'\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}'
    r'|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}'
    r'|192\.168\.\d{1,3}\.\d{1,3})\b'
)

SOURCE_FILES = [
    "../workloads/webapp/app.py",
    "../workloads/batch/reconcile.py",
]


def _abs(relative_path):
    return os.path.join(os.path.dirname(__file__), relative_path)


def test_webapp_source_no_hardcoded_ip():
    """app.py contains no private IP addresses (Finding W1-1)."""
    with open(_abs("../workloads/webapp/app.py")) as f:
        code = f.read()
    matches = PRIVATE_IP_PATTERN.findall(code)
    assert not matches, (
        f"Hardcoded IPs found in app.py: {matches}\n"
        "Fix: replace with os.environ['DB_HOST']"
    )


def test_batch_source_no_hardcoded_ip():
    """reconcile.py contains no private IP addresses (Finding B4)."""
    with open(_abs("../workloads/batch/reconcile.py")) as f:
        code = f.read()
    matches = PRIVATE_IP_PATTERN.findall(code)
    assert not matches, (
        f"Hardcoded IPs found in reconcile.py: {matches}\n"
        "Fix: replace with os.environ['DB_HOST']"
    )


def test_db_host_is_hostname_not_ip():
    """DB_HOST at runtime is a hostname, not a raw IP (service discovery working).

    In Docker Compose: DB_HOST=postgres (hostname).
    In AWS: DB_HOST=<rds-proxy-endpoint>.rds.amazonaws.com.
    Either way, it must NOT be a bare IP like 10.0.1.82.
    """
    assert not PRIVATE_IP_PATTERN.match(DB_HOST), (
        f"DB_HOST is a raw IP address ({DB_HOST}). "
        "Must be a DNS hostname so RDS Multi-AZ failover works transparently (ADR-0001)."
    )


def test_batch_source_no_hardcoded_credentials():
    """reconcile.py contains no hardcoded DB password (Finding B4)."""
    with open(_abs("../workloads/batch/reconcile.py")) as f:
        code = f.read()
    # The specific password that was found in Discovery
    assert "C0nt0s0#2019" not in code, (
        "Hardcoded password 'C0nt0s0#2019' still present in reconcile.py — "
        "must be moved to AWS Secrets Manager (ADR-0003)"
    )
    # General check: no password= with a literal value not from env
    suspicious = re.findall(r'password\s*=\s*["\'][^"\']{4,}["\']', code)
    assert not suspicious, (
        f"Possible hardcoded password in reconcile.py: {suspicious}"
    )
