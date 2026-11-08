#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import sqlite3
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest
import redis

SCRIPT = "/home/user/validate.sh"
URL = "http://127.0.0.1:5000/ingest"
DB = "/home/user/app/db/transactions.db"


def run_validator(path):
    return subprocess.run([SCRIPT, path], capture_output=True, timeout=5).returncode


def post(payload):
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=5)


def test_validate_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Validator script missing: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Validator script is not executable: {SCRIPT}"


def test_adversarial_corpus():
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = [os.path.basename(p) for p in clean_files if run_validator(p) != 0]
    evil_bypassed = [os.path.basename(p) for p in evil_files if run_validator(p) == 0]

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    assert not errors, " | ".join(errors)


def test_randomized_strict_json_validation():
    nonce = secrets.token_hex(8)
    a = random.randint(41, 900)
    c = random.randint(1, 200)

    clean = [
        json.dumps({"age": a, "clicks": c, "amount": random.randint(-10000, 10000)}),
        f'{{"age":{-a},"clicks":0,"amount":{random.randint(1, 9999)}.125}}',
        f'{{"age":{a + 1},"clicks":{c + 1},"amount":1e3,"extra":"{nonce}"}}',
    ]
    evil = [
        f'{{"age":{a}.0,"clicks":{c},"amount":1}}',
        f'{{"age":{a}e0,"clicks":{c},"amount":1}}',
        json.dumps({"age": str(a), "clicks": c, "amount": 1}),
        json.dumps({"age": None, "clicks": c, "amount": 1}),
        json.dumps({"age": True, "clicks": c, "amount": 1}),
        f'{{"age":{a},"clicks":{c}.0,"amount":1}}',
        json.dumps({"age": a, "clicks": str(c), "amount": 1}),
        json.dumps({"age": a, "clicks": None, "amount": 1}),
        json.dumps({"age": a, "clicks": False, "amount": 1}),
        json.dumps({"age": a, "clicks": c, "amount": None}),
        json.dumps({"age": a, "clicks": c, "amount": "1.5"}),
        json.dumps({"age": a, "clicks": c, "amount": True}),
        json.dumps({"age": a, "amount": 1}),
        json.dumps({"clicks": c, "amount": 1}),
        json.dumps({"age": a, "clicks": c}),
        "[]",
        "null",
        f'{{"age":{a},"clicks":{c},"amount":',
    ]

    with tempfile.TemporaryDirectory(prefix=f"validator-{nonce}-") as td:
        for i, content in enumerate(clean):
            path = os.path.join(td, f"case-{secrets.token_hex(6)}-{i}.json")
            with open(path, "w") as f:
                f.write(content)
            assert run_validator(path) == 0, f"Valid generated JSON was rejected: {content}"

        for i, content in enumerate(evil):
            path = os.path.join(td, f"case-{secrets.token_hex(6)}-{i}.json")
            with open(path, "w") as f:
                f.write(content)
            assert run_validator(path) == 1, f"Malformed generated JSON did not exit 1: {content}"


def test_config_updated():
    config_path = "/home/user/app/config.env"
    assert os.path.isfile(config_path), f"Config file missing: {config_path}"
    with open(config_path) as f:
        content = f.read()

    assert "REDIS_PORT=6379" in content, "REDIS_PORT was not updated to 6379 in config.env"
    assert "VALIDATOR_SCRIPT=/home/user/validate.sh" in content, "VALIDATOR_SCRIPT was not set correctly in config.env"

    parsed = {}
    for line in content.splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.strip().split("=", 1)
            parsed[key] = value
    assert parsed.get("REDIS_PORT") == "6379"
    assert parsed.get("VALIDATOR_SCRIPT") == SCRIPT


def test_api_service_running_and_validates():
    time.sleep(1)

    clean_payload = {"age": 25, "clicks": 10, "amount": 50.0}
    try:
        with post(clean_payload) as response:
            assert response.status in (200, 201, 202), f"Clean payload rejected by API, status: {response.status}"
    except urllib.error.URLError as e:
        pytest.fail(f"API service is not reachable or rejected clean payload: {e}")

    evil_payload = {"age": "25", "clicks": 10, "amount": 50.0}
    try:
        with post(evil_payload):
            pytest.fail("Evil payload was accepted by the API (expected HTTP error)")
    except urllib.error.HTTPError as e:
        assert e.code >= 400, f"Expected error code >= 400 for evil payload, got {e.code}"
        assert e.code == 400, f"Validator rejection must produce HTTP 400, got {e.code}"
    except urllib.error.URLError as e:
        pytest.fail(f"API service failed unexpectedly on evil payload: {e}")


def test_randomized_api_pipeline_and_sqlite_integer_columns():
    broker = redis.Redis(host="localhost", port=6379, socket_timeout=3)
    broker.ping()
    broker.delete("queue")

    base = random.randint(1000, 5000)
    amount_base = random.randint(20_000_000, 80_000_000)
    invalid = [
        {"age": str(base), "clicks": 7, "amount": amount_base + 1},
        {"age": float(base + 1), "clicks": 8, "amount": amount_base + 2},
        {"age": base + 2, "clicks": None, "amount": amount_base + 3},
        {"age": base + 3, "clicks": 9, "amount": "12.5"},
        {"age": base + 4, "clicks": True, "amount": amount_base + 5},
    ]
    valid = [
        {"age": base + 20 + i, "clicks": 30 + i, "amount": amount_base + 100 + i}
        for i in range(3)
    ]

    for payload in invalid:
        try:
            with post(payload):
                pytest.fail(f"Invalid randomized payload was accepted: {payload}")
        except urllib.error.HTTPError as e:
            assert e.code == 400, f"Invalid payload returned {e.code}, expected 400: {payload}"

    for payload in valid:
        with post(payload) as response:
            assert response.status in (200, 201, 202)

    deadline = time.time() + 10
    rows_by_amount = {}
    schema = {}
    last_error = None
    while time.time() < deadline:
        try:
            with sqlite3.connect(DB, timeout=1) as conn:
                schema = {row[1]: row[2] for row in conn.execute("PRAGMA table_info(events)")}
                rows_by_amount = {}
                for payload in valid:
                    rows_by_amount[payload["amount"]] = conn.execute(
                        "SELECT age, clicks, typeof(age), typeof(clicks) FROM events WHERE amount = ?",
                        (payload["amount"],),
                    ).fetchall()
            if schema and all(rows_by_amount.get(p["amount"]) for p in valid):
                break
        except sqlite3.Error as e:
            last_error = e
        time.sleep(0.2)

    assert schema, f"Worker did not create the events table: {last_error}"
    assert "age" in schema and "INT" in schema["age"].upper(), f"age column is not integer-typed: {schema.get('age')}"
    assert "clicks" in schema and "INT" in schema["clicks"].upper(), f"clicks column is not integer-typed: {schema.get('clicks')}"

    for payload in valid:
        rows = rows_by_amount.get(payload["amount"], [])
        assert rows, f"Accepted payload did not reach SQLite through the worker: {payload}"
        assert any(
            row[0] == payload["age"] and row[1] == payload["clicks"] and row[2] == "integer" and row[3] == "integer"
            for row in rows
        ), f"Accepted payload was not stored with SQLite integer values: {payload}, rows={rows}"

    with sqlite3.connect(DB, timeout=2) as conn:
        for payload in invalid:
            count = conn.execute("SELECT COUNT(*) FROM events WHERE amount = ?", (payload["amount"],)).fetchone()[0]
            assert count == 0, f"Rejected payload reached SQLite: {payload}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
