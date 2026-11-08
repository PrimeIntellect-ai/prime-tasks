#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import string
import base64
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/manifest_filter.py"
ORACLE_SCRIPT = "/tests/reference_filter"

def generate_random_manifest():
    if random.random() < 0.05:
        return "NOT A JSON { " + "".join(random.choices(string.ascii_letters, k=10))

    manifest = {}

    if random.random() > 0.1:
        manifest["kind"] = random.choice(["Secret", "ConfigMap", "Pod", "Deployment", "Service", "Unknown"])

    if random.random() > 0.1:
        manifest["metadata"] = {}
        if random.random() > 0.1:
            manifest["metadata"]["annotations"] = {}
            if random.random() > 0.2:
                manifest["metadata"]["annotations"]["ssh-auth"] = random.choice(["true", "false", "1", "0", "yes", "no"])
            for _ in range(random.randint(0, 3)):
                k = ''.join(random.choices(string.ascii_lowercase, k=5))
                v = ''.join(random.choices(string.ascii_lowercase, k=5))
                manifest["metadata"]["annotations"][k] = v

    if random.random() > 0.1:
        manifest["data"] = {}
        if random.random() > 0.2:
            manifest["data"]["authorized_keys"] = base64.b64encode(b"ssh-rsa AAAA...").decode('utf-8')
        for _ in range(random.randint(0, 3)):
            k = ''.join(random.choices(string.ascii_lowercase, k=5))
            v = base64.b64encode(b"random_data").decode('utf-8')
            manifest["data"][k] = v

    if random.random() < 0.05:
        return json.dumps(manifest) + " garbage"

    return json.dumps(manifest)

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script {ORACLE_SCRIPT} missing."
    assert os.access(ORACLE_SCRIPT, os.X_OK), f"Oracle script {ORACLE_SCRIPT} not executable."

    random.seed(42)

    for i in range(1000):
        input_data = generate_random_manifest()

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [ORACLE_SCRIPT],
                input=input_data.encode('utf-8'),
                capture_output=True,
                timeout=2
            )
            oracle_out = oracle_proc.stdout
        except Exception as e:
            pytest.fail(f"Oracle failed to run on iteration {i}: {e}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                [AGENT_SCRIPT],
                input=input_data.encode('utf-8'),
                capture_output=True,
                timeout=2
            )
            agent_out = agent_proc.stdout
        except Exception as e:
            pytest.fail(f"Agent script failed to run on iteration {i}: {e}")

        if oracle_out != agent_out:
            error_msg = (
                f"Mismatch on iteration {i}.\n"
                f"Input:\n{input_data}\n\n"
                f"Oracle Output:\n{oracle_out.decode('utf-8', errors='replace')}\n\n"
                f"Agent Output:\n{agent_out.decode('utf-8', errors='replace')}\n"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
