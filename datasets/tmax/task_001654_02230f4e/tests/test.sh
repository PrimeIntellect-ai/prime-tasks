#!/bin/bash
set -e
mkdir -p /logs/verifier

fail() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

[ -f /app/api.py ] || fail
[ -x /app/start.sh ] || fail

# Ensure verification executes the submitted application rather than a stale process.
pkill -f '[p]ython3 /app/api.py' 2>/dev/null || true
if ! timeout 120 /app/start.sh >/tmp/verifier_start.log 2>&1; then
    fail
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import random
import subprocess
import time
from decimal import Decimal

import pytest
import redis
import requests

BASE_URL = "http://127.0.0.1:5000/events"


def psql(sql):
    result = subprocess.run(
        ["sudo", "-u", "postgres", "psql", "-d", "app_db", "-At", "-F", "\t", "-c", sql],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def load_expected(user_ids):
    ids = sorted(set(user_ids))
    array = ",".join(str(x) for x in ids)
    sql = f"""
        SELECT user_id, id, event_type, cost::text,
               SUM(cost) OVER (PARTITION BY user_id)::text
        FROM events
        WHERE user_id = ANY(ARRAY[{array}]::int[])
        ORDER BY user_id, timestamp DESC, id DESC;
    """
    expected = {uid: {"total": Decimal("0"), "events": []} for uid in ids}
    output = psql(sql)
    if output:
        for line in output.splitlines():
            uid_s, event_id, event_type, cost, total = line.split("\t")
            uid = int(uid_s)
            expected[uid]["total"] = Decimal(total)
            expected[uid]["events"].append({
                "id": int(event_id),
                "user_id": uid,
                "event_type": event_type,
                "cost": Decimal(cost),
            })
    return expected


def assert_response(resp, expected, uid, page, limit):
    assert resp.status_code == 200
    try:
        body = resp.json()
    except Exception as exc:
        pytest.fail(f"Endpoint did not return JSON: {exc}")

    assert isinstance(body, dict)
    assert body.get("user_id") == uid
    assert "total_cost" in body and "events" in body
    assert isinstance(body["events"], list)

    actual_total = Decimal(str(body["total_cost"]))
    assert abs(actual_total - expected[uid]["total"]) <= Decimal("0.00001")

    start = (page - 1) * limit
    wanted = expected[uid]["events"][start:start + limit]
    assert len(body["events"]) == len(wanted)

    for actual, wanted_event in zip(body["events"], wanted):
        assert isinstance(actual, dict)
        assert actual.get("id") == wanted_event["id"]
        assert actual.get("user_id") == uid
        assert actual.get("event_type") == wanted_event["event_type"]
        assert abs(Decimal(str(actual.get("cost"))) - wanted_event["cost"]) <= Decimal("0.00000001")
        assert isinstance(actual.get("timestamp"), str) and actual["timestamp"]


def contains_number(value, wanted):
    if isinstance(value, (int, float, str)):
        try:
            return abs(Decimal(str(value)) - wanted) <= Decimal("0.00001")
        except Exception:
            return False
    if isinstance(value, dict):
        return any(contains_number(v, wanted) for v in value.values())
    if isinstance(value, list):
        return any(contains_number(v, wanted) for v in value)
    return False


def test_api_performance_and_correctness():
    # Preserve the original warmup behavior and connection check.
    try:
        for _ in range(5):
            response = requests.get(f"{BASE_URL}?user_id=1&page=1&limit=10", timeout=5)
            assert response.status_code == 200
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the API during warmup: {exc}")

    rng = random.SystemRandom()
    timed_uids = [rng.randint(1, 1000) for _ in range(100)]
    pagination_cases = [
        (rng.randint(1, 1000), 1, 7),
        (rng.randint(1, 1000), 2, 13),
        (rng.randint(1, 1000), 3, 17),
        (rng.randint(1, 1000), 5, 11),
    ]
    expected = load_expected(timed_uids + [case[0] for case in pagination_cases])

    # Exercise non-default limits and later pages to verify filtering, ordering,
    # and pagination rather than accepting a constant response.
    for uid, page, limit in pagination_cases:
        resp = requests.get(
            f"{BASE_URL}?user_id={uid}&page={page}&limit={limit}", timeout=5
        )
        assert_response(resp, expected, uid, page, limit)

    # Keep the original 100-request/2.5-second assertion, and additionally enforce
    # the instruction's strict 95th-percentile latency requirement.
    responses = []
    latencies = []
    errors = 0
    start_time = time.monotonic()
    for uid in timed_uids:
        request_start = time.monotonic()
        try:
            resp = requests.get(
                f"{BASE_URL}?user_id={uid}&page=1&limit=50", timeout=5
            )
            latency = time.monotonic() - request_start
            latencies.append(latency)
            responses.append((uid, resp))
            if resp.status_code != 200:
                errors += 1
        except requests.exceptions.RequestException:
            errors += 1
    total_time = time.monotonic() - start_time

    assert errors == 0, f"FAILED: {errors} out of 100 requests failed or returned non-200 status codes."
    assert total_time <= 2.5, f"FAIL: Performance threshold not met. Expected <= 2.5s, got {total_time:.3f}s"
    assert len(latencies) == 100
    p95 = sorted(latencies)[94]
    assert p95 < 0.050, f"FAIL: p95 latency must be strictly under 50ms, got {p95 * 1000:.2f}ms"

    for uid, resp in responses:
        assert_response(resp, expected, uid, 1, 50)

    # Confirm that PostgreSQL has and selects a useful events index for the
    # filtered, sorted, limited endpoint query.
    index_count = int(psql("""
        SELECT COUNT(*)
        FROM pg_indexes
        WHERE schemaname='public' AND tablename='events'
          AND indexname <> 'events_pkey';
    """) or "0")
    assert index_count > 0, "No non-primary index was created for events"

    plan = psql("""
        EXPLAIN SELECT id, user_id, event_type, cost, timestamp
        FROM events
        WHERE user_id = 500
        ORDER BY timestamp DESC, id DESC
        LIMIT 50 OFFSET 0;
    """)
    assert "Index" in plan and "events" in plan, f"Endpoint-shaped query does not use an index:\n{plan}"

    # Flush Redis, reset its counters, and repeat a user query. The second request
    # must produce a cache hit, and the cache must contain the derived aggregate.
    cache = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)
    cache.ping()
    cache.flushdb()
    cache.config_resetstat()

    cache_uid = timed_uids[0]
    first = requests.get(f"{BASE_URL}?user_id={cache_uid}&page=1&limit=50", timeout=5)
    second = requests.get(f"{BASE_URL}?user_id={cache_uid}&page=2&limit=25", timeout=5)
    assert_response(first, expected, cache_uid, 1, 50)
    assert_response(second, expected, cache_uid, 2, 25)

    stats = cache.info("stats")
    assert int(stats.get("keyspace_hits", 0)) >= 1, "Repeated aggregate query did not hit Redis"

    found_total = False
    for key in cache.scan_iter(match="*"):
        if cache.type(key) != b"string":
            continue
        raw = cache.get(key)
        if raw is None:
            continue
        text = raw.decode("utf-8", errors="replace")
        try:
            value = json.loads(text)
        except Exception:
            value = text
        if contains_number(value, expected[cache_uid]["total"]):
            found_total = True
            break
    assert found_total, "Redis did not contain the correct aggregate total"

    # Verify that requests made by the API actually scan a non-primary events index.
    psql("SELECT pg_stat_reset();")
    for page in (1, 2, 3):
        resp = requests.get(
            f"{BASE_URL}?user_id={cache_uid}&page={page}&limit=20", timeout=5
        )
        assert resp.status_code == 200
    time.sleep(0.25)
    scans = int(psql("""
        SELECT COALESCE(SUM(idx_scan), 0)
        FROM pg_stat_user_indexes
        WHERE schemaname='public' AND relname='events'
          AND indexrelname <> 'events_pkey';
    """) or "0")
    assert scans > 0, "API requests did not use the created events index"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
