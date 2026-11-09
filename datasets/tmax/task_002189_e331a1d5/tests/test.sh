#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_packer_equivalence():
    agent_script = "/home/user/packer.py"
    oracle_bin = "/app/legacy_packer"

    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is not a file."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."

    random.seed(42)

    # The spec requests 1000 fuzzing iterations.
    for i in range(1000):
        length = random.randint(1, 100000)
        data = random.randbytes(length)

        oracle_proc = subprocess.run([oracle_bin], input=data, capture_output=True)
        assert oracle_proc.returncode == 0, f"Oracle crashed on iteration {i} with input length {length}"
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run([agent_script], input=data, capture_output=True)
        if agent_proc.returncode != 0:
            stderr_snippet = agent_proc.stderr.decode(errors='ignore')[:200]
            pytest.fail(f"Agent script crashed on iteration {i} with input length {length}.\nStderr: {stderr_snippet}")

        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on iteration {i} (input length {length}).\n"
                f"Oracle output length: {len(oracle_out)}\n"
                f"Agent output length: {len(agent_out)}\n"
                f"Oracle output (first 50 bytes): {oracle_out[:50].hex()}\n"
                f"Agent output (first 50 bytes): {agent_out[:50].hex()}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
