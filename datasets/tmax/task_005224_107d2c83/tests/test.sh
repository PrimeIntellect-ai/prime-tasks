#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import tempfile

AGENT_ENTRY = ["python3", "/home/user/repo/main.py"]
N_ITERATIONS = 50
MIN_LEN = 1024
MAX_LEN = 1048576
XOR_KEY = 0x4B


def expected_output(input_bytes):
    return bytes(byte ^ XOR_KEY for byte in reversed(input_bytes))


def test_fuzz_equivalence():
    assert os.path.exists("/home/user/repo/main.py"), "Agent entry point missing"

    random.seed(42)

    for i in range(N_ITERATIONS):
        length = random.randint(MIN_LEN, MAX_LEN)
        input_bytes = random.randbytes(length)

        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            tmp.write(input_bytes)
            tmp_path = tmp.name

        try:
            oracle_out = expected_output(input_bytes)

            agent_proc = subprocess.run(
                AGENT_ENTRY + [tmp_path],
                capture_output=True,
                check=False
            )
            assert agent_proc.returncode == 0, f"Agent failed on iteration {i} with error: {agent_proc.stderr.decode(errors='replace')}"
            agent_out = agent_proc.stdout

            assert agent_out == oracle_out, (
                f"Output mismatch on iteration {i} (input length {length}).\n"
                f"Oracle output len: {len(oracle_out)}\n"
                f"Agent output len: {len(agent_out)}"
            )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
