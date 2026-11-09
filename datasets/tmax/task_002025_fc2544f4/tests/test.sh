#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import json
import time
import uuid
import random
import subprocess
import pytest

def test_pipeline_end_to_end():
    # Restart services
    manage_script = "/home/user/manage_services.sh"
    assert os.path.isfile(manage_script), "manage_services.sh script missing"

    subprocess.run([manage_script, "restart"], check=True)

    # Wait for services to be up
    time.sleep(3)

    # Clear the redis list just in case
    subprocess.run(["redis-cli", "DEL", "live_access_logs"], capture_output=True)

    # Send request
    test_user = f"test_user_{uuid.uuid4().hex[:8]}"
    test_endpoint = f"/test_endpoint_{uuid.uuid4().hex[:8]}"

    curl_cmd = [
        "curl", "-s", "-H", f"X-User-Id: {test_user}",
        f"http://127.0.0.1:8080{test_endpoint}"
    ]
    subprocess.run(curl_cmd, capture_output=True)

    # Wait for Vector to process the log
    time.sleep(3)

    # Check Redis
    redis_cmd = ["redis-cli", "LPOP", "live_access_logs"]
    result = subprocess.run(redis_cmd, capture_output=True, text=True)

    output = result.stdout.strip()
    assert output, "No data found in Redis list 'live_access_logs'"

    try:
        log_entry = json.loads(output)
    except json.JSONDecodeError:
        pytest.fail(f"Data in Redis is not valid JSON: {output}")

    assert log_entry.get("user_id") == test_user, f"Expected user_id {test_user}, got {log_entry.get('user_id')}"
    assert log_entry.get("endpoint") == test_endpoint, f"Expected endpoint {test_endpoint}, got {log_entry.get('endpoint')}"
    assert "timestamp" in log_entry, "Missing 'timestamp' in log entry"
    assert "latency" in log_entry, "Missing 'latency' in log entry"

def test_log_transform_fuzz_equivalence(tmp_path):
    agent_script = "/home/user/log_transform.py"
    oracle_script = "/tests/log_transform_oracle.py"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}"

    random.seed(42)
    users = [f"user_{i}" for i in range(10)]
    endpoints = ["/api/v1/data", "/login", "/logout", "/ping"]

    for i in range(50):
        num_lines = random.randint(50, 500)
        input_file = tmp_path / f"input_{i}.jsonl"

        with open(input_file, "w") as f:
            for _ in range(num_lines):
                ts = 1690000000.0 + random.uniform(0, 10000)
                user_id = random.choice(users) if random.random() > 0.5 else str(uuid.uuid4())
                endpoint = random.choice(endpoints)
                latency = round(random.uniform(0.01, 5.00), 3)

                record = {
                    "timestamp": f"{ts:.3f}",
                    "user_id": user_id,
                    "endpoint": endpoint,
                    "latency": latency
                }
                f.write(json.dumps(record) + "\n")

        # Run oracle
        oracle_res = subprocess.run(
            [sys.executable, oracle_script, str(input_file)],
            capture_output=True, text=True
        )
        assert oracle_res.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_res.stderr}"

        # Run agent
        agent_res = subprocess.run(
            [sys.executable, agent_script, str(input_file)],
            capture_output=True, text=True
        )
        assert agent_res.returncode == 0, f"Agent failed on iteration {i}:\n{agent_res.stderr}"

        # Compare output
        if oracle_res.stdout != agent_res.stdout:
            with open(input_file, "r") as f:
                input_data = f.read()
            pytest.fail(
                f"Mismatch on iteration {i}.\n"
                f"Input data:\n{input_data[:500]}...\n"
                f"Expected output (Oracle):\n{oracle_res.stdout[:500]}...\n"
                f"Actual output (Agent):\n{agent_res.stdout[:500]}..."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
