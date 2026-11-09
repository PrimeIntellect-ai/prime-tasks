#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest
import numpy as np

def generate_test_case():
    """Generate a random near-singular PSD matrix input string."""
    N = np.random.randint(3, 11)
    A = np.random.randn(N, N)
    PSD = (A @ A.T) * 1e-8

    input_lines = [str(N)]
    for row in PSD:
        input_lines.append(" ".join(f"{val:.15e}" for val in row))

    return "\n".join(input_lines) + "\n"

def test_runner_executable_exists():
    """Verify that the agent built the runner executable."""
    assert os.path.isfile('/home/user/runner'), "The executable /home/user/runner is missing."
    assert os.access('/home/user/runner', os.X_OK), "The file /home/user/runner is not executable."

def test_fuzz_equivalence():
    """Fuzz the agent's runner against the oracle with 500 near-singular matrices."""
    np.random.seed(42)
    oracle_path = '/tests/oracle'
    agent_path = '/home/user/runner'

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"

    for i in range(500):
        input_data = generate_test_case()

        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=input_data,
                text=True,
                capture_output=True,
                check=True,
                timeout=2
            )
            oracle_output = oracle_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i}. Input:\n{input_data}\nError: {e.stderr}")

        try:
            agent_proc = subprocess.run(
                [agent_path],
                input=input_data,
                text=True,
                capture_output=True,
                check=True,
                timeout=2
            )
            agent_output = agent_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program failed on iteration {i}. Input:\n{input_data}\nError: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on iteration {i}. Input:\n{input_data}")

        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i}.\n"
            f"Input:\n{input_data}\n"
            f"Expected (Oracle):\n{oracle_output}\n"
            f"Got (Agent):\n{agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
