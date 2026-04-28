"""Smoke: Redis connectivity and basic readiness."""


def test_redis_ping(redis_client):
    """Redis responds to PING."""
    assert redis_client.ping() is True


def test_redis_set_get(redis_client):
    """Redis can write and read a key."""
    redis_client.set("smoke_test_key", "ok", ex=10)
    assert redis_client.get("smoke_test_key") == b"ok"
    redis_client.delete("smoke_test_key")
