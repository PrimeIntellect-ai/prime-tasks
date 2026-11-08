#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import secrets
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest
import redis

FILTER_BIN = "/app/bin/filter"
FILTER_SRC = "/app/src/filter.c"


def run_filter(binary, path):
    return subprocess.run(
        [binary, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    ).returncode


def test_filter_executable_exists():
    assert os.path.isfile(FILTER_BIN), "/app/bin/filter does not exist. Did you compile the C program?"
    assert os.access(FILTER_BIN, os.X_OK), "/app/bin/filter is not executable."
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/bin/filter is not a compiled executable."


def test_filter_source_exists_and_compiles():
    assert os.path.isfile(FILTER_SRC), "/app/src/filter.c is missing."
    result = subprocess.run(
        ["gcc", "-O3", FILTER_SRC, "-o", "/tmp/rebuilt_filter", "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, "filter.c does not compile:\n" + result.stderr


def test_adversarial_corpus_filter():
    evil_dir = "/app/eval_corpus/evil"
    clean_dir = "/app/eval_corpus/clean"

    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".csv")]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".csv")]

    assert len(evil_files) > 0, "No evil corpus files found to test."
    assert len(clean_files) > 0, "No clean corpus files found to test."

    evil_bypassed = []
    for filepath in evil_files:
        if run_filter(FILTER_BIN, filepath) == 0:
            evil_bypassed.append(os.path.basename(filepath))

    clean_modified = []
    for filepath in clean_files:
        if run_filter(FILTER_BIN, filepath) != 0:
            clean_modified.append(os.path.basename(filepath))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}")

    assert not errors, "Adversarial filter failed:\n" + "\n".join(errors)


def write_csv(path, x_values, y_values):
    with open(path, "w") as f:
        for x, y in zip(x_values, y_values):
            f.write(f"{x:.12g},{y:.12g}\n")


def make_runtime_cases(directory):
    rng = random.Random(secrets.randbits(128))
    cases = []
    x_values = [400.0 + 400.0 * i / 126.0 for i in range(127)]

    # Safe spectra contain a pronounced nonlinear peak plus ordinary measurement noise.
    for _ in range(7):
        center = rng.uniform(575.0, 625.0)
        width = rng.uniform(25.0, 52.0)
        amplitude = rng.uniform(0.7, 1.8)
        baseline = rng.uniform(-0.2, 0.2)
        noise = rng.uniform(0.025, 0.055)
        y_values = [
            baseline
            + amplitude * math.exp(-((x - center) / width) ** 2)
            + rng.gauss(0.0, noise)
            for x in x_values
        ]
        path = os.path.join(directory, secrets.token_hex(12) + ".csv")
        write_csv(path, x_values, y_values)
        cases.append((path, 0))

    # Unsafe spectra are flat, affine/collinear, or numerically near-affine.
    for index in range(9):
        mode = index % 3
        offset = rng.uniform(-10.0, 10.0)
        slope = rng.uniform(-2.0, 2.0)
        if abs(slope) < 0.1:
            slope = 0.25
        if mode == 0:
            y_values = [offset for _ in x_values]
        elif mode == 1:
            y_values = [offset + slope * x for x in x_values]
        else:
            y_values = [offset + slope * x + rng.gauss(0.0, 1e-10) for x in x_values]
        path = os.path.join(directory, secrets.token_hex(12) + ".csv")
        write_csv(path, x_values, y_values)
        cases.append((path, 1))

    rng.shuffle(cases)
    return cases


def test_filter_on_runtime_generated_unlabelled_inputs():
    if not os.path.isfile("/tmp/rebuilt_filter"):
        result = subprocess.run(
            ["gcc", "-O3", FILTER_SRC, "-o", "/tmp/rebuilt_filter", "-lm"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, result.stderr

    with tempfile.TemporaryDirectory(prefix="spectra_") as directory:
        cases = make_runtime_cases(directory)
        for binary in (FILTER_BIN, "/tmp/rebuilt_filter"):
            failures = []
            for path, expected in cases:
                actual = run_filter(binary, path)
                if actual != expected:
                    failures.append((os.path.basename(path), expected, actual))
            assert not failures, f"{binary} misclassified runtime-generated CSV data: {failures}"


def test_flask_env_configuration():
    env_path = "/app/config/flask.env"
    assert os.path.isfile(env_path), f"{env_path} is missing."

    with open(env_path, "r") as f:
        content = f.read()

    assert "redis://localhost:6379" in content, "REDIS_URL in flask.env was not updated to port 6379."
    assert "redis://localhost:6380" not in content, "Old REDIS_URL port 6380 is still present in flask.env."


def test_start_sh_configuration():
    start_sh_path = "/app/start.sh"
    assert os.path.isfile(start_sh_path), f"{start_sh_path} is missing."

    with open(start_sh_path, "r") as f:
        content = f.read()

    assert "redis-server" in content, "redis-server is not being launched in start.sh."


def stop_services():
    subprocess.run(["redis-cli", "-p", "6379", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/app/app.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/app/worker.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)


def test_end_to_end_service_flow():
    stop_services()
    proc = subprocess.Popen(
        ["/app/start.sh"],
        cwd="/app",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    try:
        deadline = time.time() + 15
        api_ready = False
        redis_client = redis.Redis(host="localhost", port=6379, decode_responses=True)
        while time.time() < deadline:
            try:
                redis_client.ping()
                request = urllib.request.Request(
                    "http://localhost:5000/process",
                    data=json.dumps({"data_path": "/app/corpus/clean/clean_0.csv"}).encode(),
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                with urllib.request.urlopen(request, timeout=1) as response:
                    assert response.status == 200
                    payload = json.loads(response.read().decode())
                api_ready = True
                break
            except (OSError, urllib.error.URLError, redis.RedisError):
                time.sleep(0.25)

        assert api_ready, "start.sh did not bring up Redis and the Flask API on ports 6379 and 5000."
        assert "job_id" in payload, "Flask response did not contain a job_id."

        result_key = f"result_{payload['job_id']}"
        result = None
        deadline = time.time() + 10
        while time.time() < deadline:
            result = redis_client.get(result_key)
            if result is not None:
                break
            time.sleep(0.2)

        assert result == "success", "The worker did not consume the submitted job and write its result to Redis."
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        stop_services()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
