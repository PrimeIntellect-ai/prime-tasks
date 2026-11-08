#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import urllib.request
import pytest


def test_nginx_and_services_running():
    # Send a POST request to the Nginx reverse proxy
    url = "http://localhost:8080/upload"
    data = b"test_payload_12345"
    req = urllib.request.Request(url, data=data, method='POST')

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
    except Exception as e:
        pytest.fail(f"Failed to communicate with the API via Nginx on port 8080: {e}")

    # Check if the payload reached Redis
    try:
        redis_check = subprocess.run(
            ["redis-cli", "lpop", "data_queue"],
            capture_output=True, text=True, check=True
        )
        assert "test_payload_12345" in redis_check.stdout, "Payload not found in Redis queue. Nginx/Flask integration might be broken."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to check Redis queue: {e}")


def test_validate_data_script():
    script_path = "/home/user/validate_data.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    # This valid case retains the original positive ACCEPT assertion without the
    # >10% missing-value contradiction present in /tests/clean/clean1.csv.
    valid_path = "/tmp/valid_accept.csv"
    with open(valid_path, "w") as f:
        f.write(
            "sensor_id,timestamp,value\n"
            "1,2000,49.8\n"
            "1,2001,50.2\n"
            "2,2002,49.9\n"
            "2,2003,50.1\n"
            "4,2004,49.7\n"
            "4,2005,50.3\n"
        )

    valid_res = subprocess.run(
        ["python3", script_path, valid_path], capture_output=True, text=True
    )
    assert valid_res.returncode == 0 and valid_res.stdout.strip() == "ACCEPT", \
        "Instruction-compliant valid input was rejected"

    # After the join and active filter, clean1 has one missing value among six
    # retained rows, so the specified strictly-more-than-10% rule requires REJECT.
    clean1 = "/tests/clean/clean1.csv"
    clean1_res = subprocess.run(
        ["python3", script_path, clean1], capture_output=True, text=True
    )
    assert clean1_res.returncode == 1 and clean1_res.stdout.strip() == "REJECT", \
        "clean1.csv must be rejected because 1/6 joined active values are missing"

    evil_dir = "/tests/evil"
    evil_files = [
        os.path.join(evil_dir, f)
        for f in os.listdir(evil_dir)
        if f.endswith('.csv')
    ]

    evil_failed = []
    for ef in evil_files:
        res = subprocess.run(["python3", script_path, ef], capture_output=True, text=True)
        if res.returncode != 1 or res.stdout.strip() != "REJECT":
            evil_failed.append(os.path.basename(ef))

    if evil_failed:
        pytest.fail(
            f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: "
            + ", ".join(evil_failed)
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
