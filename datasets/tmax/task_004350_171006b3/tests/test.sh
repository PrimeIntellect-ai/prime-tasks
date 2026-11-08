#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import string
import subprocess
import time
import urllib.error
import urllib.request

import redis
from neo4j import GraphDatabase

CONFIG_PATH = "/home/user/config.json"
SANITIZER_PATH = "/home/user/sanitizer.py"
EXPECTED_CONFIG = {
    "neo4j_uri": "bolt://localhost:7687",
    "neo4j_user": "neo4j",
    "neo4j_password": "password",
    "redis_uri": "redis://localhost:6379/0",
}


def read_health():
    req = urllib.request.Request("http://localhost:5000/health")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


def run_sanitizer(value, expected):
    result = subprocess.run(
        ["python3", SANITIZER_PATH, value],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Sanitizer exited {result.returncode} for {value!r}: {result.stderr!r}"
    )
    assert result.stdout in (expected, expected + "\n", expected + "\r\n"), (
        f"Expected exactly {expected!r} for {value!r}, got stdout {result.stdout!r}"
    )


def test_config_and_real_database_connections():
    with open(CONFIG_PATH, "r") as handle:
        config = json.load(handle)

    for key, value in EXPECTED_CONFIG.items():
        assert config.get(key) == value, f"Incorrect {key}: {config.get(key)!r}"

    cache = redis.Redis.from_url(config["redis_uri"], socket_connect_timeout=3, socket_timeout=3)
    assert cache.ping() is True, "Redis did not answer PING using config.json"

    driver = GraphDatabase.driver(
        config["neo4j_uri"],
        auth=(config["neo4j_user"], config["neo4j_password"]),
        connection_timeout=5,
    )
    try:
        driver.verify_connectivity()
    finally:
        driver.close()


def test_flask_health():
    """Verify that the Flask app is up and returns status ok."""
    try:
        status, data = read_health()
        assert status == 200, f"Expected HTTP 200, got {status}: {data}"
        assert data.get("status") == "ok", f"Expected status 'ok', got {data}"
    except Exception as exc:
        assert False, f"Failed to connect to Flask health endpoint: {exc}"


def test_health_is_backed_by_configured_services():
    """A static endpoint that always reports ok must not pass."""
    with open(CONFIG_PATH, "rb") as handle:
        original = handle.read()

    broken = dict(EXPECTED_CONFIG)
    broken["redis_uri"] = "redis://127.0.0.1:1/0"
    try:
        with open(CONFIG_PATH, "w") as handle:
            json.dump(broken, handle)
        status, data = read_health()
        assert status != 200 or data.get("status") != "ok", (
            "Health endpoint still reported ok with an unreachable configured Redis service"
        )
    finally:
        with open(CONFIG_PATH, "wb") as handle:
            handle.write(original)

    deadline = time.time() + 8
    last = None
    while time.time() < deadline:
        try:
            last = read_health()
            if last[0] == 200 and last[1].get("status") == "ok":
                break
        except Exception as exc:
            last = exc
        time.sleep(0.25)
    assert isinstance(last, tuple) and last[0] == 200 and last[1].get("status") == "ok", (
        f"Health endpoint did not recover after restoring config: {last}"
    )


def test_sanitizer_executable():
    """Verify that the sanitizer script exists and is executable."""
    assert os.path.exists(SANITIZER_PATH), f"{SANITIZER_PATH} does not exist"
    assert stat.S_ISREG(os.stat(SANITIZER_PATH).st_mode), f"{SANITIZER_PATH} is not a regular file"
    assert os.access(SANITIZER_PATH, os.X_OK), f"{SANITIZER_PATH} is not executable"


def test_sanitizer_adversarial_corpus():
    """Verify exact classifications for every shipped corpus entry."""
    clean_corpus = "/home/user/corpora/clean.csv"
    evil_corpus = "/home/user/corpora/evil.csv"
    assert os.path.exists(clean_corpus), f"Clean corpus {clean_corpus} missing"
    assert os.path.exists(evil_corpus), f"Evil corpus {evil_corpus} missing"

    with open(clean_corpus, "r") as handle:
        clean_lines = [line.strip() for line in handle if line.strip()]
    with open(evil_corpus, "r") as handle:
        evil_lines = [line.strip() for line in handle if line.strip()]

    for line in clean_lines:
        run_sanitizer(line, "SAFE")
    for line in evil_lines:
        run_sanitizer(line, "EVIL")


def test_sanitizer_runtime_generated_cases():
    """Exercise unseen cases with expected answers derived by the verifier."""
    rng = random.SystemRandom()

    def token(length=14):
        return "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(length))

    clean = []
    for _ in range(30):
        value = token()
        clean.extend([
            value,
            f"{value} Holdings",
            f"{value}_Data-{rng.randrange(2000, 2100)}",
            f"{value} & Sons",
        ])

    keywords = ["CALL", "YIELD", "DELETE", "REMOVE", "SET", "MERGE", "CREATE"]
    evil = []
    for keyword in keywords:
        for _ in range(6):
            mixed = "".join(
                char.lower() if rng.randrange(2) else char.upper() for char in keyword
            )
            prefix = token(10)
            suffix = token(10)
            evil.append(f"{prefix}' {mixed} n.{suffix} = 1")
    for _ in range(20):
        evil.append(f"{token()} ' OR 1=1 // {token()}")

    rng.shuffle(clean)
    rng.shuffle(evil)
    for value in clean:
        run_sanitizer(value, "SAFE")
    for value in evil:
        run_sanitizer(value, "EVIL")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
