#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import pytest

AGENT_SCRIPT = "/home/user/forge_token.py"
ORACLE_SCRIPT = "/tests/oracle_forge.py"
N_ITERATIONS = 200

def test_agent_script_exists_and_executable():
    """
    Verify that the student's script exists, is a file, and is executable.
    """
    assert os.path.exists(AGENT_SCRIPT), f"Final state failure: The script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"Final state failure: {AGENT_SCRIPT} is not a file."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Final state failure: The script {AGENT_SCRIPT} is not executable."

def test_fuzz_equivalence():
    """
    Verify that the agent script behaves bit-exactly identically to the oracle script
    on N random inputs (username and role_id).
    """
    random.seed(42)

    for i in range(N_ITERATIONS):
        username_len = random.randint(4, 12)
        username = ''.join(random.choices(string.ascii_letters + string.digits, k=username_len))
        role_id = random.randint(0, 9999)

        oracle_cmd = ["/usr/bin/python3", ORACLE_SCRIPT, username, str(role_id)]
        oracle_proc = subprocess.run(oracle_cmd, capture_output=True)
        assert oracle_proc.returncode == 0, (
            f"Oracle failed on input ({username}, {role_id}) with error: "
            f"{oracle_proc.stderr.decode(errors='replace')}"
        )
        oracle_out = oracle_proc.stdout

        agent_cmd = ["/usr/bin/python3", AGENT_SCRIPT, username, str(role_id)]
        agent_proc = subprocess.run(agent_cmd, capture_output=True)

        assert agent_proc.returncode == 0, (
            f"Agent script failed on input ({username}, {role_id}).\n"
            f"Stderr: {agent_proc.stderr.decode(errors='replace')}"
        )

        agent_out = agent_proc.stdout

        assert agent_out == oracle_out, (
            f"Mismatch on iteration {i+1}!\n"
            f"Input Username: '{username}'\n"
            f"Input Role ID: {role_id}\n"
            f"Expected Output (Oracle): {oracle_out.decode(errors='replace')!r}\n"
            f"Actual Output (Agent): {agent_out.decode(errors='replace')!r}\n"
            "Ensure your script extracts the correct 'aud' and 'override_code' from the image, "
            "uses the 'none' algorithm, correctly base64url-encodes without padding, and outputs ONLY the token."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
