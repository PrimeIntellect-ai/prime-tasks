#!/bin/bash
set -e
mkdir -p /logs/verifier

cleanup() {
    pkill -f '/app/experiment_api.py' 2>/dev/null || true
    pkill -f '/app/worker.py' 2>/dev/null || true
    redis-cli -p 6379 shutdown nosave >/dev/null 2>&1 || true
}
cleanup
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import subprocess
import time
import pytest
import requests


def generate_random_input():
    length = random.randint(0, 100)
    data = []
    for _ in range(length):
        row = {}
        # 10% chance to drop f1
        if random.random() > 0.1:
            # 10% chance for null
            row["f1"] = random.uniform(-10.0, 10.0) if random.random() > 0.1 else None
        # 10% chance to drop f2
        if random.random() > 0.1:
            row["f2"] = random.uniform(-10.0, 10.0) if random.random() > 0.1 else None
        data.append(row)
    return data


def run_oracle(data):
    oracle_path = "/tests/oracle_preprocessor.py"
    assert os.path.isfile(oracle_path), f"Oracle script {oracle_path} is missing."
    proc = subprocess.run(
        ["python3", oracle_path],
        input=json.dumps(data),
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, f"Oracle failed: {proc.stderr}"
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Oracle script output invalid JSON\nOutput: {proc.stdout}")


def test_fuzz_equivalence():
    random.seed(42)
    oracle_path = "/tests/oracle_preprocessor.py"
    agent_path = "/home/user/preprocessor.py"

    assert os.path.isfile(oracle_path), f"Oracle script {oracle_path} is missing."
    assert os.path.isfile(agent_path), f"Agent script {agent_path} is missing."
    assert os.access(agent_path, os.X_OK), f"Agent script {agent_path} is not executable."

    for i in range(500):
        input_data = generate_random_input()
        input_str = json.dumps(input_data)

        oracle_proc = subprocess.run(
            ["python3", oracle_path], input=input_str, text=True,
            capture_output=True, timeout=10
        )
        agent_proc = subprocess.run(
            ["python3", agent_path], input=input_str, text=True,
            capture_output=True, timeout=10
        )

        assert agent_proc.returncode == 0, f"Agent script failed on input: {input_str}\nError: {agent_proc.stderr}"

        try:
            oracle_out = json.loads(oracle_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle script output invalid JSON on input: {input_str}\nOutput: {oracle_proc.stdout}")

        try:
            agent_out = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent script output invalid JSON on input: {input_str}\nOutput: {agent_proc.stdout}")

        assert agent_out == oracle_out, f"Mismatch on input {input_str}\nExpected: {oracle_out}\nGot: {agent_out}"


def test_worker_fixed():
    worker_path = "/app/worker.py"
    assert os.path.isfile(worker_path), f"{worker_path} is missing."

    with open(worker_path, "r") as f:
        content = f.read()

    assert "port=6379" in content.replace(" ", ""), "Worker Redis port not fixed to 6379 in /app/worker.py"
    assert "http://localhost:5000/log_metric" in content, "Worker API URL not fixed to http://localhost:5000/log_metric in /app/worker.py"


def test_end_to_end_pipeline():
    start_script = "/app/start_services.sh"
    assert os.path.isfile(start_script), f"{start_script} is missing."
    assert os.access(start_script, os.X_OK), f"{start_script} is not executable."

    started = subprocess.run(
        [start_script], text=True, capture_output=True, timeout=15
    )
    assert started.returncode == 0, (
        f"Service startup failed. stdout={started.stdout!r} stderr={started.stderr!r}"
    )

    base_url = "http://localhost:5000"
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(base_url + "/metrics", timeout=1)
            if response.status_code == 200:
                break
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    else:
        pytest.fail(f"API did not become ready on port 5000: {last_error}")

    batch = [
        {"f1": -9.0, "f2": 1.0},
        {"f1": None, "f2": 3.0},
        {"f1": 4.0},
        {"f1": 5.0, "f2": None},
    ]
    expected = run_oracle(batch)

    response = requests.post(base_url + "/ingest", json=batch, timeout=3)
    assert response.status_code == 200, f"Ingest failed: {response.status_code} {response.text}"
    assert response.json() == {"status": "queued"}

    deadline = time.time() + 20
    observed = []
    while time.time() < deadline:
        response = requests.get(base_url + "/metrics", timeout=2)
        assert response.status_code == 200
        observed = response.json()
        if expected in observed:
            break
        time.sleep(0.25)
    else:
        pytest.fail(f"Worker did not post the expected metric to the API. Expected {expected}, observed {observed}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
