#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import zlib
import tempfile
import pytest

def test_decompress_script_exists():
    assert os.path.exists("/home/user/decompress.py"), "The script /home/user/decompress.py does not exist."

def test_fuzz_equivalence():
    agent_script = "/home/user/decompress.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.exists(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script missing: {oracle_script}"

    random.seed(42)
    num_iterations = 50

    for i in range(num_iterations):
        # Generate random payload
        length = random.randint(100, 5000)
        payload = bytes(random.getrandbits(8) for _ in range(length))

        # Create valid backup file
        compressed = zlib.compress(payload)
        obfuscated = bytes([b ^ 115 for b in compressed])
        file_content = b"BKP9" + obfuscated

        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            tmp.write(file_content)
            tmp_path = tmp.name

        try:
            # Run oracle
            oracle_proc = subprocess.run(
                ["python3", oracle_script, tmp_path],
                capture_output=True,
                check=True
            )
            oracle_output = oracle_proc.stdout

            # Run agent
            agent_proc = subprocess.run(
                ["python3", agent_script, tmp_path],
                capture_output=True
            )
            agent_output = agent_proc.stdout

            assert agent_proc.returncode == 0, f"Agent script failed with return code {agent_proc.returncode} on iteration {i}. Stderr: {agent_proc.stderr.decode(errors='replace')}"

            if oracle_output != agent_output:
                # Truncate outputs for display if they are too long
                def truncate(data, limit=100):
                    if len(data) > limit:
                        return data[:limit] + b"... (truncated)"
                    return data

                error_msg = (
                    f"Output mismatch on iteration {i} (payload length {length}).\n"
                    f"Oracle output: {truncate(oracle_output)}\n"
                    f"Agent output: {truncate(agent_output)}"
                )
                pytest.fail(error_msg)
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
