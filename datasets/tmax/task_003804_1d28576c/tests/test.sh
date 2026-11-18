#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/encoder.py"
ORACLE_SCRIPT = "/tests/oracle_encoder"
N_ITERATIONS = 200

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script is missing at {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"
    assert os.access(ORACLE_SCRIPT, os.X_OK), f"Oracle script at {ORACLE_SCRIPT} is not executable"

    random.seed(42)  # Fixed seed for reproducibility

    for i in range(N_ITERATIONS):
        # Generate random length between 1 and 2048
        length = random.randint(1, 2048)
        # Generate random binary data
        input_data = bytes(random.getrandbits(8) for _ in range(length))

        # Run oracle
        oracle_proc = subprocess.run(
            [ORACLE_SCRIPT],
            input=input_data,
            capture_output=True,
            check=False
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"
        oracle_output = oracle_proc.stdout

        # Run agent script
        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT],
            input=input_data,
            capture_output=True,
            check=False
        )

        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}. Stderr: {agent_proc.stderr.decode(errors='replace')}"
        agent_output = agent_proc.stdout

        # Compare outputs
        if oracle_output != agent_output:
            # Truncate output for display if it's too long
            display_input = input_data[:32].hex() + ("..." if len(input_data) > 32 else "")
            display_oracle = oracle_output[:64].decode(errors='replace') + ("..." if len(oracle_output) > 64 else "")
            display_agent = agent_output[:64].decode(errors='replace') + ("..." if len(agent_output) > 64 else "")

            pytest.fail(
                f"Mismatch on iteration {i} (length {length}).\n"
                f"Input (hex start): {display_input}\n"
                f"Expected (Oracle): {display_oracle}\n"
                f"Got (Agent):       {display_agent}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
