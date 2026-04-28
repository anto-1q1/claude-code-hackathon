"""
Shared fixtures — all endpoints/credentials read from env vars.
Same test suite runs locally (Docker Compose) and in cloud (AWS).

Local defaults match docker-compose.yml.
Cloud: set env vars in CI or pass via --env-file.
"""
import os
import boto3
import pytest
import psycopg2
import redis as redis_lib
import requests
from botocore.client import Config


# ── Config ────────────────────────────────────────────────────────────────────

def cfg(key, default):
    return os.environ.get(key, default)


WEBAPP_URL       = cfg("WEBAPP_URL",       "http://localhost:5000")
DB_HOST          = cfg("DB_HOST",          "localhost")
DB_PORT          = int(cfg("DB_PORT",      "5432"))
DB_NAME          = cfg("DB_NAME",          "contoso")
DB_USER          = cfg("DB_USER",          "contoso_app")
DB_PASSWORD      = cfg("DB_PASSWORD",      "local_dev_only")
REDIS_URL        = cfg("REDIS_URL",        "redis://localhost:6379/0")
S3_ENDPOINT      = cfg("S3_ENDPOINT",      "http://localhost:9000")
S3_BUCKET_WEBAPP = cfg("S3_BUCKET_WEBAPP", "contoso-webapp-reports-prod")
S3_BUCKET_BATCH  = cfg("S3_BUCKET_BATCH",  "contoso-batch-output-prod")
AWS_KEY          = cfg("AWS_ACCESS_KEY_ID",     "minioadmin")
AWS_SECRET       = cfg("AWS_SECRET_ACCESS_KEY", "minioadmin")


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(scope="session")
def webapp_url():
    return WEBAPP_URL


@pytest.fixture(scope="session")
def db_conn():
    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD,
    )
    yield conn
    conn.close()


@pytest.fixture(scope="session")
def redis_client():
    client = redis_lib.from_url(REDIS_URL)
    yield client
    client.close()


@pytest.fixture(scope="session")
def s3_client():
    kwargs = dict(
        aws_access_key_id=AWS_KEY,
        aws_secret_access_key=AWS_SECRET,
        region_name="eu-west-1",
    )
    if S3_ENDPOINT:
        kwargs["endpoint_url"] = S3_ENDPOINT
        kwargs["config"] = Config(signature_version="s3v4")
    return boto3.client("s3", **kwargs)


@pytest.fixture(scope="session")
def http():
    session = requests.Session()
    session.timeout = 10
    return session
