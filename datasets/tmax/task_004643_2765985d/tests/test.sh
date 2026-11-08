#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

ORACLE_PATH = "/tests/kinematics_oracle"
AGENT_BINARY = "/home/user/kinematics/target/release/kinematics"
LOG_FILE = "/home/user/audio_analysis.log"

def run_binary(binary_path, input_data):
    result = subprocess.run(
        [binary_path],
        input=input_data,
        text=True,
        capture_output=True,
        check=False
    )
    return result.stdout.strip(), result.returncode

def test_audio_analysis_log():
    assert os.path.exists(LOG_FILE), f"Log file missing at {LOG_FILE}"

    # Expected CSV from the audio
    expected_csv = "0.0,2.5\n1.0,3.8\n2.0,4.1\n3.0,6.0\n4.0,5.5\n"

    # Get expected output from oracle
    expected_output, rc = run_binary(ORACLE_PATH, expected_csv)
    assert rc == 0, "Oracle failed to process the expected audio CSV"

    with open(LOG_FILE, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, f"Log file content mismatch.\nExpected:\n{expected_output}\n\nActual:\n{actual_output}"

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_BINARY), f"Agent binary missing at {AGENT_BINARY}"
    assert os.access(AGENT_BINARY, os.X_OK), f"Agent binary at {AGENT_BINARY} is not executable"

    random.seed(42)

    for i in range(200):
        num_lines = random.randint(10, 100)
        lines = []
        t = 0.0
        for _ in range(num_lines):
            t += random.uniform(0.1, 10.0)
            v = random.uniform(-50.0, 50.0)
            lines.append(f"{t:.4f},{v:.4f}")

        input_data = "\n".join(lines) + "\n"

        oracle_out, oracle_rc = run_binary(ORACLE_PATH, input_data)
        agent_out, agent_rc = run_binary(AGENT_BINARY, input_data)

        assert agent_rc == oracle_rc, f"Return code mismatch on test case {i}. Oracle: {oracle_rc}, Agent: {agent_rc}"
        assert agent_out == oracle_out, (
            f"Output mismatch on test case {i}.\n"
            f"Input:\n{input_data}\n"
            f"Oracle Output:\n{oracle_out}\n"
            f"Agent Output:\n{agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
