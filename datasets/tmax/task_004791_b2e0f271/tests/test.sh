#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import json
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/scaler.py"
ORACLE_SCRIPT = "/tests/oracle_scaler.py"
NUM_ITERATIONS = 500

def generate_random_input():
    length = random.randint(1, 200)
    return [random.uniform(-1000.0, 1000.0) for _ in range(length)]

def run_script(cmd, input_data):
    try:
        result = subprocess.run(
            cmd,
            input=json.dumps(input_data),
            text=True,
            capture_output=True,
            check=True,
            timeout=5
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script execution failed for {cmd}\nStderr: {e.stderr}")
    except json.JSONDecodeError as e:
        pytest.fail(f"Script {cmd} did not output valid JSON.\nOutput: {result.stdout}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script {cmd} timed out.")

def test_scaler_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    random.seed(42)

    for i in range(NUM_ITERATIONS):
        input_data = generate_random_input()

        oracle_output = run_script([sys.executable, ORACLE_SCRIPT], input_data)
        agent_output = run_script([sys.executable, AGENT_SCRIPT], input_data)

        if oracle_output != agent_output:
            pytest.fail(
                f"Mismatch on iteration {i+1}.\n"
                f"Input array length: {len(input_data)}\n"
                f"Input data (first 5 elements): {input_data[:5]}\n"
                f"Expected output (oracle): {oracle_output}\n"
                f"Actual output (agent): {agent_output}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
