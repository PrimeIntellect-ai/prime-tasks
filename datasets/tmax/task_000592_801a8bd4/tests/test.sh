#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import socket
import time
import pytest

def generate_random_payload():
    parts = []
    tokens = [
        "X-Internal-Trace-ID: some-id-123",
        "Subject: Random Subject",
        "http://insecure.local/path?q=1",
        "Just some random text.",
        "\r\n",
        "\n"
    ]

    for _ in range(random.randint(5, 50)):
        if random.random() < 0.3:
            parts.append(random.choice(tokens))
        else:
            parts.append(''.join(random.choices(string.ascii_letters + string.digits + " \t", k=random.randint(10, 50))))

    sep = random.choice(["\n", "\r\n"])
    return sep.join(parts).encode('utf-8')

def test_fuzz_sanitize_equivalence():
    agent_script = "/home/user/sanitize.py"
    oracle_script = "/tests/oracle_sanitize"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} not found."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} not found."

    random.seed(42)

    for i in range(500):
        payload = generate_random_payload()

        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=payload,
            capture_output=True,
            timeout=5
        )
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=payload,
            capture_output=True,
            timeout=5
        )
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            error_msg = f"Mismatch on iteration {i}.\n"
            error_msg += f"Input:\n{payload.decode('utf-8', errors='replace')}\n"
            error_msg += f"Oracle output:\n{oracle_out.decode('utf-8', errors='replace')}\n"
            error_msg += f"Agent output:\n{agent_out.decode('utf-8', errors='replace')}\n"
            pytest.fail(error_msg)

def test_end_to_end_flow():
    setup_script = "/home/user/setup_env.sh"
    assert os.path.isfile(setup_script), f"{setup_script} not found."
    assert os.access(setup_script, os.X_OK), f"{setup_script} is not executable."

    subprocess.run([setup_script], check=True)
    time.sleep(2)

    payloads = [
        b"Subject: E2E Test 1\nhttp://insecure.local/\n",
        b"X-Internal-Trace-ID: 999\nSubject: E2E Test 2\nBody\n",
        b"No subject here\nJust http://insecure.local/ link\n",
        b"Subject: E2E Test 4\r\nWindows line endings\r\n",
        b"Subject: E2E Test 5\nMultiple http://insecure.local/ http://insecure.local/\n"
    ]

    for payload in payloads:
        try:
            with socket.create_connection(("127.0.0.1", 10025), timeout=5) as sock:
                sock.sendall(payload)
        except Exception as e:
            pytest.fail(f"Failed to send payload to Ingress service on port 10025: {e}")

    time.sleep(3)

    log_file = "/app/egress_out.log"
    assert os.path.isfile(log_file), f"Egress log file {log_file} not found. The flow did not complete."

    with open(log_file, "rb") as f:
        log_content = f.read()

    assert b"https://secure.local/" in log_content, "Expected transformed URL not found in egress log."
    assert b"http://insecure.local/" not in log_content, "Insecure URL found in egress log, not transformed."
    assert b"X-Processed-By: SecRelay-v1" in log_content, "Expected header not found in egress log."
    assert b"X-Internal-Trace-ID: " not in log_content, "Trace ID header was not removed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
