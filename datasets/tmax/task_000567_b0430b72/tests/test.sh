#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest
import redis

RUST_BIN = "/home/user/artifact_filter/target/release/artifact_filter"
PROJECT_DIR = "/home/user/artifact_filter"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
API_URL = "http://127.0.0.1:8080/api/artifacts"


def run_cli(path):
    return subprocess.run([RUST_BIN, path], capture_output=True, text=True, timeout=15)


def post_json(data):
    body = json.dumps(data, allow_nan=True).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, response.read(), response.headers
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(), exc.headers


def redis_snapshot(client):
    return {key: client.dump(key) for key in client.scan_iter("*")}


def redis_contains_json(client, expected):
    for key in client.scan_iter("*"):
        if client.type(key) != b"string":
            continue
        value = client.get(key)
        try:
            if json.loads(value.decode("utf-8")) == expected:
                return True
        except (UnicodeDecodeError, ValueError, TypeError):
            pass
    return False


def test_rust_binary_exists():
    assert os.path.isfile(RUST_BIN), f"Rust binary not found at {RUST_BIN}"
    assert os.access(RUST_BIN, os.X_OK), f"Rust binary at {RUST_BIN} is not executable"
    with open(RUST_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "artifact_filter must be a compiled native executable"
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Cargo.toml")), "Cargo.toml is missing"
    assert os.path.isfile(os.path.join(PROJECT_DIR, "src", "main.rs")), "Rust source is missing"


def test_adversarial_corpus_rust_cli():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))

    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_CORPUS_DIR}."
    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_CORPUS_DIR}."

    clean_failed = []
    for f in clean_files:
        res = run_cli(f)
        if res.returncode != 0 or "ACCEPT" not in res.stdout:
            clean_failed.append(os.path.basename(f))

    evil_bypassed = []
    for f in evil_files:
        res = run_cli(f)
        if res.returncode != 1 or "REJECT" not in res.stdout:
            evil_bypassed.append(os.path.basename(f))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_bypassed)}")
    assert not errors, " | ".join(errors)


def test_generated_inputs_at_unpredictable_paths():
    token = uuid.uuid4().hex
    base = random.uniform(2.0, 20.0)
    stable_losses = [base + random.uniform(-0.01, 0.01) for _ in range(100)]

    cases = [
        ({"gradient_norms": [random.uniform(0.0, 4.0) for _ in range(100)], "loss_values": stable_losses, "missing_ratio": 0.05}, 0, "ACCEPT"),
        ({"gradient_norms": [1000.0] * 100, "loss_values": stable_losses, "missing_ratio": 0.0}, 0, "ACCEPT"),
        ({"gradient_norms": [1.0] * 20, "loss_values": [1000000.0] * 100, "missing_ratio": 0.0}, 0, "ACCEPT"),
        ({"gradient_norms": [1.0] * 100, "loss_values": stable_losses, "missing_ratio": 0.050001}, 1, "REJECT"),
        ({"gradient_norms": [1000.0] * 100 + [0.01], "loss_values": stable_losses, "missing_ratio": 0.0}, 1, "REJECT"),
        ({"gradient_norms": [1.0, float("nan")], "loss_values": stable_losses, "missing_ratio": 0.0}, 1, "REJECT"),
        ({"gradient_norms": [1.0], "loss_values": [1.0, float("inf")], "missing_ratio": 0.0}, 1, "REJECT"),
        ({"gradient_norms": [1.0] * 100, "loss_values": [0.0 if i % 2 == 0 else 1000.0 for i in range(100)], "missing_ratio": 0.0}, 1, "REJECT"),
    ]
    random.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix=f"artifact-{token}-") as directory:
        for index, (payload, expected_code, expected_text) in enumerate(cases):
            path = os.path.join(directory, f"{uuid.uuid4().hex}-{index}.dat")
            with open(path, "w") as f:
                json.dump(payload, f, allow_nan=True)
            result = run_cli(path)
            assert result.returncode == expected_code, (
                f"generated case {index} returned {result.returncode}, expected {expected_code}; "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert expected_text in result.stdout


def test_services_and_status_file():
    status_path = "/home/user/system_status.log"
    assert os.path.isfile(status_path), "system_status.log is missing"
    with open(status_path) as f:
        assert "READY" in f.read(), "system_status.log does not contain READY"

    client = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=3)
    assert client.ping() is True, "Redis is not available on its default local port"

    for port in (5000, 8080):
        with socket.create_connection(("127.0.0.1", port), timeout=3):
            pass


def test_end_to_end_flow():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))
    if not clean_files or not evil_files:
        pytest.skip("Missing corpora for E2E tests.")

    with open(clean_files[0], "r") as f:
        clean_data = f.read().encode("utf-8")
    req_clean = urllib.request.Request(API_URL, data=clean_data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req_clean, timeout=10) as response:
            assert response.status == 200, f"Expected 200 OK for clean payload, got {response.status}"
            assert "nginx" in response.headers.get("Server", "").lower(), "Port 8080 is not being served through Nginx"
    except urllib.error.HTTPError as e:
        pytest.fail(f"Clean payload failed with status {e.code}")
    except Exception as e:
        pytest.fail(f"Could not connect to API for clean payload E2E test: {e}")

    with open(evil_files[0], "r") as f:
        evil_data = f.read().encode("utf-8")
    req_evil = urllib.request.Request(API_URL, data=evil_data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req_evil, timeout=10) as response:
            pytest.fail(f"Expected 406 Not Acceptable for evil payload, but got {response.status}")
    except urllib.error.HTTPError as e:
        assert e.code == 406, f"Expected 406 Not Acceptable for evil payload, got {e.code}"
    except Exception as e:
        pytest.fail(f"Could not connect to API for evil payload E2E test: {e}")


def test_runtime_subprocess_and_redis_integration():
    client = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=3)
    client.flushdb()

    token = uuid.uuid4().hex
    backup = f"{RUST_BIN}.verifier-{token}"
    marker = f"/tmp/artifact-filter-calls-{token}"
    captured = f"/tmp/artifact-filter-payload-{token}.json"
    force_reject = f"/tmp/artifact-filter-force-{token}"

    os.replace(RUST_BIN, backup)
    wrapper = f'''#!/bin/sh
printf '%s\\n' "$1" >> {marker!r}
cp -- "$1" {captured!r}
if [ -f {force_reject!r} ]; then
    echo REJECT
    exit 1
fi
exec {backup!r} "$@"
'''
    with open(RUST_BIN, "w") as f:
        f.write(wrapper)
    os.chmod(RUST_BIN, 0o755)

    clean = {
        "gradient_norms": [random.uniform(0.1, 2.0) for _ in range(80)],
        "loss_values": [random.uniform(4.0, 4.1) for _ in range(80)],
        "missing_ratio": random.uniform(0.001, 0.02),
    }
    rejected = {
        "gradient_norms": [1.0] * 80,
        "loss_values": [random.uniform(1.0, 2.0) for _ in range(80)],
        "missing_ratio": random.uniform(0.2, 0.4),
    }

    try:
        status, _, headers = post_json(clean)
        assert status == 200, f"generated clean API payload returned {status}"
        assert "nginx" in headers.get("Server", "").lower(), "request did not pass through Nginx"
        assert os.path.isfile(marker), "Flask did not invoke the artifact_filter subprocess"
        with open(captured) as f:
            assert json.load(f) == clean, "Flask did not pass the incoming payload to artifact_filter"
        assert redis_contains_json(client, clean), "accepted artifact was not written to Redis"
        accepted_snapshot = redis_snapshot(client)

        status, _, _ = post_json(rejected)
        assert status == 406, f"generated anomalous API payload returned {status}, expected 406"
        with open(captured) as f:
            assert json.load(f) == rejected, "rejected payload was not checked by artifact_filter"
        assert redis_snapshot(client) == accepted_snapshot, "rejected artifact modified Redis"

        open(force_reject, "w").close()
        status, _, _ = post_json(clean)
        assert status == 406, "Flask ignored a rejecting artifact_filter subprocess exit code"
        assert redis_snapshot(client) == accepted_snapshot, "subprocess-rejected artifact was saved to Redis"

        with open(marker) as f:
            calls = [line for line in f if line.strip()]
        assert len(calls) >= 3, "artifact_filter was not invoked for every incoming payload"
    finally:
        try:
            os.unlink(RUST_BIN)
        except FileNotFoundError:
            pass
        os.replace(backup, RUST_BIN)
        for path in (marker, captured, force_reject):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
