import os
import time
import psycopg2
import redis as redis_lib
from flask import Flask, jsonify, session

app = Flask(__name__)
app.secret_key = os.environ.get("SESSION_SECRET", "local-dev-secret-change-in-prod")

# Sessions on Redis — fixes Discovery finding W1-3 (local disk sessions block scaling)
_redis = redis_lib.from_url(os.environ["REDIS_URL"])

# DB connection uses env var — fixes Discovery finding W1-1 (hardcoded IP)
def _db_conn():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", 5432)),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
    )


@app.route("/health")
def health():
    """Liveness + readiness probe used by ECS and docker-compose healthcheck."""
    checks = {}

    # DB check
    try:
        conn = _db_conn()
        conn.close()
        checks["db"] = "ok"
    except Exception as exc:
        checks["db"] = f"error: {exc}"

    # Redis check
    try:
        _redis.ping()
        checks["redis"] = "ok"
    except Exception as exc:
        checks["redis"] = f"error: {exc}"

    healthy = all(v == "ok" for v in checks.values())
    return jsonify({
        "status": "healthy" if healthy else "degraded",
        "env": os.environ.get("ENV", "unknown"),
        "checks": checks,
        "timestamp": int(time.time()),
    }), 200 if healthy else 503


@app.route("/api/warmup")
def warmup():
    """Cache warm-up endpoint called by batch job before reconciliation.
    Decoupled from cron via EventBridge in cloud (Discovery finding B1).
    """
    _redis.set("portfolio_cache_warmed", "1", ex=3600)
    return jsonify({"warmed": True}), 200


@app.route("/")
def index():
    return jsonify({"service": "contoso-webapp", "env": os.environ.get("ENV")}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
