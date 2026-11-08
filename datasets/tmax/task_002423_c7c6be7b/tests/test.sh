#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import random
import subprocess
import pytest

def test_py_kmer_counter_installed():
    """Verify that the py_kmer_counter package is installed and functioning."""
    try:
        import py_kmer_counter
        res = py_kmer_counter.count_3mers('ACGT')
        assert type(res) is dict, "count_3mers should return a dict"
    except ImportError:
        pytest.fail("py_kmer_counter is not installed or cannot be imported.")
    except Exception as e:
        pytest.fail(f"py_kmer_counter.count_3mers failed with exception: {e}")

def test_solve_script_fuzz_equivalence():
    """Fuzz test /home/user/solve.py against the test-only oracle."""
    agent_script = "/home/user/solve.py"
    oracle_script = "/tests/solve_oracle.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)
    chars = ['A', 'C', 'G', 'T']

    for i in range(100):
        length = random.randint(100, 1000)
        test_input = "".join(random.choices(chars, k=length))

        oracle_proc = subprocess.run(
            [sys.executable, oracle_script],
            input=test_input,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i} with error: {oracle_proc.stderr}"
        oracle_output = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            [sys.executable, agent_script],
            input=test_input,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i} with error: {agent_proc.stderr}"
        agent_output = agent_proc.stdout.strip()

        assert agent_output == oracle_output, (
            f"Output mismatch on iteration {i}.\n"
            f"Input length: {length}\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output: {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
