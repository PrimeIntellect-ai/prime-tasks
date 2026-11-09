#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import signal
import subprocess
import time
import uuid

import psycopg2
import pytest
import redis
import requests

API_URL = "http://127.0.0.1:8080/api/graph"
SERVER_PROCESS = None


def request_category(category, timeout=3):
    return requests.get(API_URL, params={"category": category}, timeout=timeout)


def kill_port_8080_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if local.rsplit(":", 1)[-1].upper() == "1F90" and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in victims:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(0.5)


def test_01_api_server_is_running_before_verifier_restart():
    """Preserve the requirement that the agent left a server listening on port 8080."""
    try:
        response = request_category("tech", timeout=2)
        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the API server on 127.0.0.1:8080. Is it running?")


def test_02_source_binary_and_launch_artifact():
    """Ensure the submitted C artifact exists, uses the required APIs, and is what gets exercised."""
    global SERVER_PROCESS

    source_path = "/app/api_server.c"
    binary_path = "/app/api_server"
    assert os.path.isfile(source_path), "/app/api_server.c is missing"
    assert os.path.isfile(binary_path), "/app/api_server is missing"
    assert os.access(binary_path, os.X_OK), "/app/api_server is not executable"

    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/api_server must be a compiled executable"

    with open(source_path, encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert source.strip(), "/app/api_server.c is empty"

    # Remove C comments so a comment containing the required terms is insufficient.
    uncommented = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    uncommented = re.sub(r"//[^\n]*", " ", uncommented)
    assert re.search(r"\b(?:ROW_NUMBER|RANK)\s*\(\s*\)\s*OVER\s*\(", uncommented, re.I), \
        "The PostgreSQL query must use ROW_NUMBER() or RANK() as a window function"
    assert re.search(r"\bPQexec(?:Params)?\s*\(", uncommented), "C source does not query PostgreSQL with libpq"
    assert re.search(r"\bredisCommand\s*\(", uncommented), "C source does not access Redis with hiredis"

    kill_port_8080_listeners()
    redis.Redis(host="127.0.0.1", port=6379, decode_responses=True).delete("graph:tech")
    log = open("/tmp/api_server_verifier.log", "ab", buffering=0)
    SERVER_PROCESS = subprocess.Popen(
        [binary_path], cwd="/app", stdin=subprocess.DEVNULL, stdout=log, stderr=log
    )

    last_error = None
    for _ in range(50):
        if SERVER_PROCESS.poll() is not None:
            break
        try:
            response = request_category("tech", timeout=1)
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.2)

    details = ""
    try:
        with open("/tmp/api_server_verifier.log", "rb") as f:
            details = f.read()[-4000:].decode(errors="replace")
    except OSError:
        pass
    pytest.fail(f"The submitted /app/api_server did not start successfully: {last_error}\n{details}")


def test_03_api_tech_category_response():
    """Preserve the original exact checks for the static tech fixture."""
    response = request_category("tech", timeout=2)
    assert response.status_code == 200
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type application/json, got {content_type}"

    try:
        data = response.json()
    except (ValueError, json.JSONDecodeError):
        pytest.fail(f"Response body is not valid JSON: {response.text}")

    assert data.get("category") == "tech", "Expected category to be 'tech'"
    nodes = data.get("nodes")
    assert isinstance(nodes, list), "Expected 'nodes' to be a list"
    assert len(nodes) == 2, f"Expected 2 nodes for 'tech', got {len(nodes)}"
    assert nodes[0].get("user_id") == 1
    assert nodes[1].get("user_id") == 2

    alice = nodes[0]
    assert alice.get("user_name") == "Alice"
    alice_followers = alice.get("top_followers", [])
    assert len(alice_followers) == 3, "Expected exactly 3 top followers for Alice"
    assert alice_followers[0] == {"follower_id": 4, "score": 99}
    assert alice_followers[1] == {"follower_id": 2, "score": 95}
    assert alice_followers[2] == {"follower_id": 3, "score": 80}

    bob = nodes[1]
    assert bob.get("user_name") == "Bob"
    bob_followers = bob.get("top_followers", [])
    assert len(bob_followers) == 2, "Expected exactly 2 followers for Bob"
    assert bob_followers[0] == {"follower_id": 3, "score": 60}
    assert bob_followers[1] == {"follower_id": 1, "score": 50}


def test_04_dynamic_categories_database_query_and_cache():
    """Exercise unpredictable categories/data, exact top-three behavior, and both cache paths."""
    token = uuid.uuid4().hex[:12]
    category_a = f"audit_{token}_a"
    category_b = f"audit_{token}_b"
    base = 900000000 + (int(token[:6], 16) % 50000000)
    u1, u2, u3 = base + 1, base + 2, base + 3

    conn = psycopg2.connect(host="127.0.0.1", port=5432, user="admin", password="password", dbname="graphdb")
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.executemany(
            "INSERT INTO users (id, name, category) VALUES (%s, %s, %s)",
            [(u2, "Second User", category_a), (u1, "O'Brien", category_a), (u3, "Other Category", category_b)],
        )
        cur.executemany(
            "INSERT INTO follows (follower_id, followee_id, engagement_score) VALUES (%s, %s, %s)",
            [
                (base + 101, u1, 91), (base + 102, u1, 105),
                (base + 103, u1, 44), (base + 104, u1, 88),
                (base + 105, u2, 17), (base + 106, u2, 73),
                (base + 107, u3, 62), (base + 108, u3, 81),
                (base + 109, u3, 70), (base + 110, u3, 12),
            ],
        )

    expected_a = {
        "category": category_a,
        "nodes": [
            {"user_id": u1, "user_name": "O'Brien", "top_followers": [
                {"follower_id": base + 102, "score": 105},
                {"follower_id": base + 101, "score": 91},
                {"follower_id": base + 104, "score": 88},
            ]},
            {"user_id": u2, "user_name": "Second User", "top_followers": [
                {"follower_id": base + 106, "score": 73},
                {"follower_id": base + 105, "score": 17},
            ]},
        ],
    }
    expected_b = {
        "category": category_b,
        "nodes": [{"user_id": u3, "user_name": "Other Category", "top_followers": [
            {"follower_id": base + 108, "score": 81},
            {"follower_id": base + 109, "score": 70},
            {"follower_id": base + 107, "score": 62},
        ]}],
    }

    cache = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    cache.delete(f"graph:{category_a}", f"graph:{category_b}")

    # A preloaded value must be returned directly, proving Redis is checked first.
    sentinel = {"category": category_a, "nodes": [], "cache_probe": token}
    cache.set(f"graph:{category_a}", json.dumps(sentinel, separators=(",", ":")))
    response = request_category(category_a)
    assert response.status_code == 200
    assert "application/json" in response.headers.get("Content-Type", "")
    assert response.json() == sentinel, "Server did not return the pre-existing Redis value"

    # Cache miss must query the unpredictable PostgreSQL rows and create an exact result.
    cache.delete(f"graph:{category_a}")
    response = request_category(category_a)
    assert response.status_code == 200
    assert response.json() == expected_a
    cached_raw = cache.get(f"graph:{category_a}")
    assert cached_raw is not None and json.loads(cached_raw) == expected_a
    assert cache.ttl(f"graph:{category_a}") == -1, "Cached graph must have no expiration"

    # A second independently generated category rules out a fixed-category implementation.
    response_b = request_category(category_b)
    assert response_b.status_code == 200
    assert response_b.json() == expected_b
    assert json.loads(cache.get(f"graph:{category_b}")) == expected_b
    assert cache.ttl(f"graph:{category_b}") == -1

    # Change PostgreSQL after caching: the cached response must remain unchanged.
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO follows (follower_id, followee_id, engagement_score) VALUES (%s, %s, %s)",
            (base + 111, u1, 999),
        )
    assert request_category(category_a).json() == expected_a

    # After eviction, the same executable must query PostgreSQL again and reflect the change.
    cache.delete(f"graph:{category_a}")
    expected_a_updated = json.loads(json.dumps(expected_a))
    expected_a_updated["nodes"][0]["top_followers"] = [
        {"follower_id": base + 111, "score": 999},
        {"follower_id": base + 102, "score": 105},
        {"follower_id": base + 101, "score": 91},
    ]
    assert request_category(category_a).json() == expected_a_updated
    conn.close()


def test_05_redis_caching_original_fixture():
    """Preserve the original graph:tech Redis assertions."""
    request_category("tech", timeout=2)
    result = subprocess.run(["redis-cli", "GET", "graph:tech"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to execute redis-cli"
    redis_output = result.stdout.strip()
    assert redis_output != "" and redis_output != "(nil)", "Redis key 'graph:tech' is missing or empty"
    try:
        cached_data = json.loads(redis_output)
    except json.JSONDecodeError:
        pytest.fail(f"Cached data in Redis is not valid JSON: {redis_output}")
    assert cached_data.get("category") == "tech", "Cached JSON does not match expected structure"
    assert "nodes" in cached_data, "Cached JSON missing 'nodes'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
