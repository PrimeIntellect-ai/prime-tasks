#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import base64
import os
import random
import string
import subprocess
import pytest

ORACLE_PATH = "/tests/doc_extractor_oracle"
AGENT_PATH = "/home/user/doc_extractor"

def test_makefile_fixed():
    """Check that the Makefile in libb64 was fixed."""
    makefile_path = "/app/libb64-1.2.1/src/Makefile"
    assert os.path.isfile(makefile_path), f"File {makefile_path} does not exist."

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "cencode.c" in content, f"The typo in {makefile_path} was not fixed ('cencode.c' not found)."
    assert "cencd.c" not in content, f"The typo 'cencd.c' is still present in {makefile_path}."

def generate_fuzz_input(seed):
    """Generate a random ASCII text with valid [B64]...[/B64] blocks."""
    random.seed(seed)
    length = random.randint(100, 10000)
    chars = string.ascii_letters + string.digits + " \n\t.,!?"

    parts = []
    num_blocks = random.randint(0, 20)

    for _ in range(num_blocks + 1):
        chunk_len = random.randint(10, length // (num_blocks + 1) + 10)
        chunk = "".join(random.choices(chars, k=chunk_len))
        parts.append(chunk)

    result = ""
    for i in range(num_blocks):
        result += parts[i]
        b64_len = random.randint(1, 500)
        b64_data = bytes(random.choices(range(256), k=b64_len))
        encoded = base64.b64encode(b64_data).decode('ascii')
        result += f"[B64]{encoded}[/B64]"
    result += parts[-1]

    return result.encode('utf-8')

def test_fuzz_equivalence():
    """Test that the agent program produces the exact same output as the oracle."""
    assert os.path.isfile(AGENT_PATH), f"Agent program {AGENT_PATH} does not exist."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program {AGENT_PATH} is not executable."
    assert os.path.isfile(ORACLE_PATH), f"Oracle program {ORACLE_PATH} does not exist."

    for i in range(500):
        inp = generate_fuzz_input(i)

        oracle_proc = subprocess.run([ORACLE_PATH], input=inp, capture_output=True)
        agent_proc = subprocess.run([AGENT_PATH], input=inp, capture_output=True)

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Agent return code {agent_proc.returncode} != Oracle {oracle_proc.returncode} on seed {i}"
        )

        if agent_proc.stdout != oracle_proc.stdout:
            pytest.fail(
                f"Output mismatch on seed {i}.\n"
                f"Input length: {len(inp)} bytes.\n"
                f"Oracle output length: {len(oracle_proc.stdout)} bytes.\n"
                f"Agent output length: {len(agent_proc.stdout)} bytes.\n"
                f"Input starts with: {inp[:100]!r}..."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
