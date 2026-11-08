#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/archive_tracker.sh"
ORACLE_SCRIPT = "/tests/oracle.sh"
N_TESTS = 1000

def test_fuzz_equivalence():
    """Test that the agent script is bit-exactly identical to the oracle on random inputs."""
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(N_TESTS):
            filepath = os.path.join(tmpdir, f"fuzz_{i}.bin")

            # Determine input type based on distribution
            r = random.random()
            if r < 0.10:
                # 10% empty
                data = b""
            elif r < 0.35:
                # 25% starts with \x7fELF
                length = random.randint(4, 128)
                data = b"\x7fELF" + bytes(random.choices(range(256), k=length - 4))
            else:
                # 65% purely random
                length = random.randint(1, 128)
                data = bytes(random.choices(range(256), k=length))

            with open(filepath, "wb") as f:
                f.write(data)

            # Run oracle
            oracle_res = subprocess.run(
                [ORACLE_SCRIPT, filepath],
                capture_output=True,
                text=True
            )
            oracle_out = oracle_res.stdout.strip()

            # Run agent
            agent_res = subprocess.run(
                [AGENT_SCRIPT, filepath],
                capture_output=True,
                text=True
            )
            agent_out = agent_res.stdout.strip()

            if oracle_out != agent_out:
                pytest.fail(
                    f"Mismatch on fuzz input {i} (length {len(data)}).\n"
                    f"Oracle output: {oracle_out!r}\n"
                    f"Agent output: {agent_out!r}\n"
                    f"Agent stderr: {agent_res.stderr!r}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
