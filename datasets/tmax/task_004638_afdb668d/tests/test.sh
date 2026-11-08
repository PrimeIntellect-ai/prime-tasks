#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import random
import secrets
import subprocess
import tempfile
import time
import pytest

BINARY_PATH = "/app/vendored/net-analyzer/target/release/net-analyzer"
OUTPUT_PATH = "/tmp/analysis.json"
HEALTH_PATH = "/tmp/analyzer.health"


def extract_drop_count(data):
    accepted_keys = {
        "drop", "drops", "drop_count", "dropped", "dropped_count",
        "timeout", "timeouts", "timeout_count"
    }
    found = []

    def visit(value):
        if isinstance(value, dict):
            for key, child in value.items():
                normalized = str(key).strip().lower().replace("-", "_").replace(" ", "_")
                if normalized in accepted_keys:
                    assert isinstance(child, int) and not isinstance(child, bool), \
                        f"Drop/timeout count field {key!r} must be an integer, found {child!r}"
                    found.append(child)
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(data)
    assert found, "Analysis JSON contains no drop/timeout count field"
    assert len(set(found)) == 1, f"Analysis JSON contains conflicting drop counts: {found}"
    return found[0]


def load_analysis():
    assert os.path.exists(OUTPUT_PATH), f"Output {OUTPUT_PATH} not found"
    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_PATH} is not valid JSON")


def test_bashrc_env_var():
    bashrc_path = '/home/user/.bashrc'
    assert os.path.exists(bashrc_path), f"{bashrc_path} does not exist"
    with open(bashrc_path, 'r') as f:
        content = f.read()
    assert 'ROUTER_LOG_PATH' in content, "ROUTER_LOG_PATH not found in .bashrc"


def test_acl_permissions():
    log_path = "/app/secure_logs/router.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist"

    # Check ACL for the directory
    dir_result = subprocess.run(["getfacl", "/app/secure_logs"], capture_output=True, text=True)
    assert "user:user:r" in dir_result.stdout, "User does not have read ACL on /app/secure_logs"
    assert "user:user:--x" in dir_result.stdout or "user:user:r-x" in dir_result.stdout or "user:user:rwx" in dir_result.stdout, "User does not have execute ACL on /app/secure_logs"

    # Check ACL for the file
    file_result = subprocess.run(["getfacl", log_path], capture_output=True, text=True)
    assert "user:user:r" in file_result.stdout, f"User does not have read ACL on {log_path}"


def test_health_file():
    health_path = '/tmp/analyzer.health'
    assert os.path.exists(health_path), f"Health file {health_path} not found"
    with open(health_path, 'r') as f:
        content = f.read()
    assert 'OK' in content, f"Health file does not contain 'OK'. Found: {content}"


def test_analysis_json():
    json_path = '/tmp/analysis.json'
    assert os.path.exists(json_path), f"Output {json_path} not found"
    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not valid JSON")


def test_binary_processes_supplied_log_and_counts_timeouts():
    assert os.path.exists(BINARY_PATH), f"Binary not found at {BINARY_PATH}. Did you compile with --release?"
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is not a regular file"
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable"

    rng = random.Random(secrets.randbits(128))
    expected_drops = rng.randint(2, 11)
    records = [f"EVENT {i}: Normal routing operation {secrets.token_hex(4)}\n" for i in range(2000)]
    for i in range(expected_drops):
        records.append(f"EVENT {2000 + i}: TIMEOUT occurred {secrets.token_hex(4)}\n")
    rng.shuffle(records)
    expected_drops_from_input = sum("TIMEOUT" in line for line in records)

    fd, log_path = tempfile.mkstemp(prefix="router-verifier-", suffix=".log")
    try:
        with os.fdopen(fd, "w") as f:
            f.writelines(records)

        for path in (OUTPUT_PATH, HEALTH_PATH):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        env = os.environ.copy()
        env["ROUTER_LOG_PATH"] = log_path
        result = subprocess.run(
            [BINARY_PATH], env=env, capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, \
            f"Binary failed on verifier log with return code {result.returncode}. Stderr: {result.stderr}"

        data = load_analysis()
        actual_drops = extract_drop_count(data)
        assert actual_drops == expected_drops_from_input, \
            f"Expected {expected_drops_from_input} drops, found {actual_drops} in {data!r}"

        assert os.path.exists(HEALTH_PATH), "Binary did not create the health file at startup"
        with open(HEALTH_PATH, "r") as f:
            health = f.read()
        assert "OK" in health, f"Health file does not contain 'OK'. Found: {health}"
    finally:
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass


def test_binary_execution_time():
    binary_path = "/app/vendored/net-analyzer/target/release/net-analyzer"
    assert os.path.exists(binary_path), f"Binary not found at {binary_path}. Did you compile with --release?"
    assert os.path.isfile(binary_path), f"{binary_path} is not a regular file"
    assert os.access(binary_path, os.X_OK), f"{binary_path} is not executable"

    for path in (OUTPUT_PATH, HEALTH_PATH):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["ROUTER_LOG_PATH"] = "/app/secure_logs/router.log"

    start = time.time()
    result = subprocess.run([binary_path], env=env, capture_output=True, text=True)
    duration = time.time() - start

    assert result.returncode == 0, f"Binary execution failed with return code {result.returncode}. Stderr: {result.stderr}"
    assert duration <= 0.5, f"Execution time {duration:.3f}s exceeded threshold of 0.5s"

    data = load_analysis()
    expected_drops = 0
    with open("/app/secure_logs/router.log", "r") as f:
        for line in f:
            expected_drops += "TIMEOUT" in line
    actual_drops = extract_drop_count(data)
    assert actual_drops == expected_drops, \
        f"Expected {expected_drops} drops for router.log, found {actual_drops} in {data!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
