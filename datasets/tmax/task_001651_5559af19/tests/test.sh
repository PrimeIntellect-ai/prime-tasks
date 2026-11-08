#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import json
import urllib.request
import socket
import redis
import pytest
import random
import tempfile
import uuid


def check_port(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('127.0.0.1', port)) == 0


def test_services_running():
    assert check_port(8080), "Nginx is not listening on port 8080"
    assert check_port(5000), "Flask is not listening on port 5000"
    assert check_port(6379), "Redis is not listening on port 6379"


def test_nginx_proxy_to_flask_and_redis():
    # Connect to Redis and clear the queue first
    try:
        r = redis.Redis(host='127.0.0.1', port=6379, db=0, socket_connect_timeout=2)
        r.ping()
        r.delete('sensor_jobs')
    except Exception as e:
        pytest.fail(f"Failed to connect to Redis: {e}")

    # Make POST request through Nginx
    data = json.dumps({"filepath": "/test_path_123"}).encode('utf-8')
    req = urllib.request.Request(
        "http://127.0.0.1:8080/api/enqueue",
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status in [200, 201, 202, 204], f"Unexpected HTTP status code: {response.status}"
    except Exception as e:
        pytest.fail(f"HTTP POST to Nginx failed: {e}")

    # Check Redis for the pushed job
    try:
        job = r.lpop('sensor_jobs')
        assert job is not None, "No job found in Redis 'sensor_jobs' queue. The API did not push the payload correctly."
        assert job.decode('utf-8') == "/test_path_123", f"Unexpected job payload in Redis: {job.decode('utf-8')}"
    except Exception as e:
        pytest.fail(f"Failed to verify Redis queue: {e}")


def test_detector_binary_exists():
    assert os.path.isfile("/app/detector"), "/app/detector binary does not exist. Did you compile it?"
    assert os.access("/app/detector", os.X_OK), "/app/detector is not executable."


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]

    assert len(clean_files) > 0, "No clean files found in corpus"
    assert len(evil_files) > 0, "No evil files found in corpus"

    clean_failed = []
    for cf in clean_files:
        res = subprocess.run(["/app/detector", cf], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        res = subprocess.run(["/app/detector", ef], capture_output=True)
        if res.returncode != 1:
            evil_failed.append(os.path.basename(ef))

    error_msg = []
    if clean_failed:
        error_msg.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed[:5])}")
    if evil_failed:
        error_msg.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed[:5])}")

    assert not clean_failed and not evil_failed, " | ".join(error_msg)


def reference_result(rows):
    m = 0.0
    c = 0.0
    n = len(rows)
    for _ in range(1000):
        dm = 0.0
        dc = 0.0
        for x, y in rows:
            error = m * x + c - y
            dm += error * x
            dc += error
        dm *= 2.0 / n
        dc *= 2.0 / n
        m -= 0.01 * dm
        c -= 0.01 * dc
    mse = sum((m * x + c - y) ** 2 for x, y in rows) / n
    return (1, "REJECT", mse) if mse > 5.0 else (0, "ACCEPT", mse)


def test_detector_source_and_generated_inputs():
    assert os.path.isfile("/app/detector.c"), "/app/detector.c does not exist"
    assert os.path.getsize("/app/detector.c") > 0, "/app/detector.c is empty"
    with open("/app/detector", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/detector is not a compiled binary"

    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="telemetry-check-") as td:
        rebuilt = os.path.join(td, uuid.uuid4().hex)
        build = subprocess.run(
            ["gcc", "-O2", "/app/detector.c", "-o", rebuilt, "-lm"],
            capture_output=True,
            text=True,
            timeout=20
        )
        assert build.returncode == 0, f"detector.c did not compile: {build.stderr}"

        cases = []
        for want_high in (False, True):
            made = 0
            attempts = 0
            while made < 5 and attempts < 500:
                attempts += 1
                n = rng.randint(45, 115)
                slope = rng.uniform(-2.5, 3.0)
                intercept = rng.uniform(-3.0, 3.0)
                sigma = rng.uniform(3.8, 6.0) if want_high else rng.uniform(0.05, 0.8)
                rows = []
                for _ in range(n):
                    x = rng.uniform(0.0, 6.0)
                    y = slope * x + intercept + rng.gauss(0.0, sigma)
                    rows.append((x, y))
                expected_code, expected_text, mse = reference_result(rows)
                if (want_high and mse > 8.0) or (not want_high and mse < 3.0):
                    cases.append((rows, expected_code, expected_text))
                    made += 1
            assert made == 5, "Could not construct sufficiently separated detector cases"

        rng.shuffle(cases)
        for rows, expected_code, expected_text in cases:
            path = os.path.join(td, uuid.uuid4().hex + ".csv")
            with open(path, "w", encoding="utf-8") as f:
                f.write("X,Y\n")
                for x, y in rows:
                    f.write(f"{x:.17g},{y:.17g}\n")

            for executable in ("/app/detector", rebuilt):
                result = subprocess.run(
                    [executable, path], capture_output=True, text=True, timeout=10
                )
                assert result.returncode == expected_code, (
                    f"{executable} returned {result.returncode}, expected {expected_code} "
                    f"for generated CSV {os.path.basename(path)}"
                )
                assert result.stdout.strip() == expected_text, (
                    f"{executable} printed {result.stdout!r}, expected {expected_text!r}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
