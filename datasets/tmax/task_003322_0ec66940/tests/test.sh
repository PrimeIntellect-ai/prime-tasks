#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import string
import sys
import pytest

def test_route_script_exists_and_executable():
    """Verify that the agent script exists and is executable."""
    path = "/home/user/route.py"
    assert os.path.isfile(path), f"Expected script {path} does not exist."
    assert os.access(path, os.X_OK), f"Expected script {path} to be executable."

def test_fuzz_equivalence():
    """Fuzz test comparing the agent script to the oracle on 500 inputs."""
    agent_script = "/home/user/route.py"
    oracle_script = "/tests/oracle_router.py"

    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} missing."

    random.seed(42)
    inputs = []

    valid_chars = string.ascii_letters + string.digits + "_"

    # Generate 350 valid inputs (70%)
    for _ in range(350):
        length = random.randint(1, 30)
        module = "".join(random.choices(valid_chars, k=length))
        inputs.append(f"/load/{module}")

    # Generate 150 invalid inputs (30%)
    for _ in range(150):
        choice = random.randint(1, 4)
        if choice == 1:
            # Invalid characters
            inputs.append("/load/" + "".join(random.choices(valid_chars, k=5)) + "-" + "".join(random.choices(valid_chars, k=5)))
        elif choice == 2:
            # Wrong prefix
            inputs.append("/api/load/" + "".join(random.choices(valid_chars, k=5)))
        elif choice == 3:
            # Missing leading slash
            inputs.append("load/" + "".join(random.choices(valid_chars, k=5)))
        else:
            # Extra slashes
            inputs.append("/load/" + "".join(random.choices(valid_chars, k=5)) + "/" + "".join(random.choices(valid_chars, k=5)))

    random.shuffle(inputs)

    for i, inp in enumerate(inputs):
        oracle_proc = subprocess.run([sys.executable, oracle_script, inp], capture_output=True, text=True)
        agent_proc = subprocess.run([agent_script, inp], capture_output=True, text=True)

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input {i}: {inp!r}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output:  {agent_out!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
