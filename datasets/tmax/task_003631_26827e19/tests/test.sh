#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

AGENT_EXECUTABLE = "/home/user/mc_estimator"
ORACLE_EXECUTABLE = "/tests/oracle_mc_estimator"

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_EXECUTABLE), f"Agent executable not found at {AGENT_EXECUTABLE}"
    assert os.access(AGENT_EXECUTABLE, os.X_OK), f"Agent executable {AGENT_EXECUTABLE} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_EXECUTABLE), f"Oracle executable not found at {ORACLE_EXECUTABLE}"
    assert os.access(ORACLE_EXECUTABLE, os.X_OK), f"Oracle executable {ORACLE_EXECUTABLE} is not executable"

    random.seed(42)
    num_iterations = 100
    cases = []

    # Obtain all expected outputs before running the agent, then remove the
    # uploaded oracle so the submitted executable cannot delegate to it.
    for i in range(num_iterations):
        N = random.randint(10, 500)
        floats = [random.uniform(0.0, 40.0) for _ in range(N)]
        input_str = " ".join(f"{f:.6f}" for f in floats)
        input_bytes = (input_str + "\n").encode("utf-8")

        try:
            oracle_proc = subprocess.run(
                [ORACLE_EXECUTABLE],
                input=input_bytes,
                capture_output=True,
                timeout=5,
                check=True
            )
            oracle_output = oracle_proc.stdout.decode("utf-8").strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on iteration {i+1}")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i+1} with error: {e.stderr.decode('utf-8')}")

        cases.append((i, N, input_str, input_bytes, oracle_output))

    os.unlink(ORACLE_EXECUTABLE)

    for i, N, input_str, input_bytes, oracle_output in cases:
        try:
            agent_proc = subprocess.run(
                [AGENT_EXECUTABLE],
                input=input_bytes,
                capture_output=True,
                timeout=5,
                check=True
            )
            agent_output = agent_proc.stdout.decode("utf-8").strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on iteration {i+1}")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program failed on iteration {i+1} with error: {e.stderr.decode('utf-8')}")

        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i+1} (N={N}).\n"
            f"Input (first 100 chars): {input_str[:100]}...\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output: {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
