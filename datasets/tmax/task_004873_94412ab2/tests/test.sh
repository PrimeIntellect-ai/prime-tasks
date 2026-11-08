#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import socket
import subprocess
import pytest

EXPECTED_SUMMARY = """HOST=gateway.internal.cloud
PORT=8222
CODE=ERR_KEY_SILENT_DROP_99x
"""

def test_migration_summary():
    summary_path = "/home/user/migration_summary.txt"
    assert os.path.exists(summary_path), f"File {summary_path} does not exist"
    with open(summary_path, "r") as f:
        content = f.read()

    assert content.strip() == EXPECTED_SUMMARY.strip(), "Migration summary content is incorrect"

def test_supervisor_script_exists():
    script_path = "/home/user/supervisor.sh"
    assert os.path.exists(script_path), f"Supervisor script {script_path} does not exist"

def test_rust_source_exists():
    src_path = "/home/user/gateway/src/main.rs"
    assert os.path.exists(src_path), f"Rust source code {src_path} does not exist"

def test_server_benchmark_and_correctness():
    start = time.time()
    successes = 0
    while time.time() - start < 5.0:
        try:
            s = socket.socket()
            s.settimeout(0.1)
            s.connect(('127.0.0.1', 8222))
            data = s.recv(1024).decode('utf-8')
            if data == "ERR_KEY_SILENT_DROP_99x\n":
                successes += 1
            s.close()
        except Exception:
            pass
    rps = successes / 5.0
    assert rps >= 100, f"RPS {rps} is less than required 100"

def test_supervisor_restarts_server():
    # Find the PID of the gateway_simulator
    try:
        pid_str = subprocess.check_output(["pidof", "gateway_simulator"]).decode('utf-8').strip()
        pids = pid_str.split()
        for pid in pids:
            os.kill(int(pid), 9) # SIGKILL
    except subprocess.CalledProcessError:
        pytest.fail("gateway_simulator is not running")

    # Wait for up to 2 seconds for it to restart
    restarted = False
    for _ in range(20):
        time.sleep(0.1)
        try:
            subprocess.check_output(["pidof", "gateway_simulator"])
            restarted = True
            break
        except subprocess.CalledProcessError:
            continue

    assert restarted, "Supervisor script did not restart the gateway_simulator within 2 seconds"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
