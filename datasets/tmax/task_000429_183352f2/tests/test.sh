#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_near_singular_matrix():
    m00 = random.uniform(0.5, 10.0)
    m01 = random.uniform(0.5, 10.0)
    m10 = random.uniform(0.5, 10.0)

    # To make it near singular: m00*m11 ~= m01*m10 => m11 ~= m01*m10/m00
    m11 = (m01 * m10) / m00

    # Add small noise
    m11 += random.uniform(-0.05, 0.05)

    # Clamp to [0.0, 10.0]
    m11 = max(0.0, min(10.0, m11))

    return f"{m00:.4f},{m01:.4f},{m10:.4f},{m11:.4f}"

def test_fast_solver_fuzz_equivalence():
    agent_script = "/home/user/fast_solver.py"
    oracle_script = "/tests/oracle_solver.py"
    audio_file = "/app/system_vibration.wav"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"
    assert os.path.isfile(audio_file), f"Audio file not found at {audio_file}"

    random.seed(42)

    for i in range(100):
        matrix_str = generate_near_singular_matrix()

        oracle_cmd = ["python3", oracle_script, audio_file, matrix_str]
        agent_cmd = ["python3", agent_script, audio_file, matrix_str]

        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, check=True, timeout=5)
            oracle_out = oracle_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {matrix_str}. Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {matrix_str}")

        try:
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, check=True, timeout=5)
            agent_out = agent_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input {matrix_str}. Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {matrix_str}")

        assert agent_out == oracle_out, (
            f"Output mismatch on run {i+1}/100.\n"
            f"Input matrix: {matrix_str}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Actual (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
