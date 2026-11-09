#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import base64
import random
import subprocess
import urllib.request
import urllib.error
import pytest

def test_nginx_proxy_and_services():
    """Verify that Nginx, Flask, and Redis are running and properly configured."""
    req = urllib.request.Request("http://127.0.0.1:8080/api/upload", method="POST")
    req.add_header("Content-Type", "application/json")
    data = json.dumps({"filename": "test.txt", "payload_b64": "SGVsbG8="}).encode("utf-8")

    try:
        with urllib.request.urlopen(req, data=data, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200 OK, got {response.status}"
    except urllib.error.HTTPError as e:
        pytest.fail(f"HTTP error from Nginx proxy: {e.code} {e.reason}. Check proxy_pass configuration.")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx on 8080 or proxy failed: {e.reason}. Are services running?")

def test_auditor_fuzz_equivalence():
    """Verify the agent's path_auditor.py against the isolated oracle using fuzz equivalence."""
    agent_script = "/home/user/path_auditor.py"
    oracle_script = "/tests/oracle_auditor"

    assert os.path.exists(agent_script), f"Agent script {agent_script} not found."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} not found."

    random.seed(1337)
    inputs = []

    # Generate 10000 fuzz inputs
    for _ in range(10000):
        # Generate filename
        fn_choice = random.random()
        if fn_choice < 0.2:
            filename = "../../etc/passwd"
        elif fn_choice < 0.4:
            filename = "foo/../../var/uploads/secret.txt"
        elif fn_choice < 0.6:
            filename = "/absolute/path/file"
        elif fn_choice < 0.8:
            filename = "valid_file_" + "".join(random.choices("abcdefghijklmnopqrstuvwxyz", k=5))
        else:
            filename = "".join(random.choices("abcdefghijklmnopqrstuvwxyz", k=10)) + ".txt"

        # Generate payload
        pl_choice = random.random()
        if pl_choice < 0.1:
            payload_b64 = "invalid_b64_string!@#"
        else:
            raw_bytes = bytearray(random.getrandbits(8) for _ in range(random.randint(5, 50)))
            if pl_choice < 0.4:
                idx = random.randint(0, len(raw_bytes))
                raw_bytes[idx:idx] = b"\xDE\xAD\xBE\xEF"
            payload_b64 = base64.b64encode(raw_bytes).decode('utf-8')

        inputs.append(json.dumps({"filename": filename, "payload_b64": payload_b64}))

    input_data = "\n".join(inputs) + "\n"

    oracle_proc = subprocess.run([oracle_script], input=input_data, text=True, capture_output=True)
    assert oracle_proc.returncode == 0, f"Oracle script failed with error: {oracle_proc.stderr}"
    oracle_output = oracle_proc.stdout.strip().split("\n")

    agent_proc = subprocess.run([agent_script], input=input_data, text=True, capture_output=True)
    assert agent_proc.returncode == 0, f"Agent script failed with error: {agent_proc.stderr}"
    agent_output = agent_proc.stdout.strip().split("\n")

    assert len(oracle_output) == len(agent_output), "Output line counts differ between oracle and agent script."

    for i, (o_line, a_line) in enumerate(zip(oracle_output, agent_output)):
        if o_line != a_line:
            pytest.fail(
                f"Mismatch on input line {i+1}:\n"
                f"Input:  {inputs[i]}\n"
                f"Oracle: {o_line}\n"
                f"Agent:  {a_line}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
