#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/audit_tool.py"
ORACLE_BINARY = "/tests/oracle_audit_tool"

def test_agent_script_exists_and_executable():
    """Test that the agent's script exists and is executable."""
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

def test_agent_script_shebang():
    """Test that the agent's script has a python3 shebang."""
    with open(AGENT_SCRIPT, "r", encoding="utf-8") as f:
        first_line = f.readline().strip()
    assert first_line.startswith("#!") and "python3" in first_line, f"Agent script {AGENT_SCRIPT} does not have a valid python3 shebang. Found: {first_line}"

def test_fuzz_equivalence():
    """Fuzz the agent's script against oracle-derived expected outputs."""
    assert os.path.isfile(ORACLE_BINARY), f"Oracle binary {ORACLE_BINARY} is missing."
    assert os.access(ORACLE_BINARY, os.X_OK), f"Oracle binary {ORACLE_BINARY} is not executable."

    random.seed(42)
    iterations = 500
    min_len = 1
    max_len = 256
    printable_chars = string.printable
    cases = []

    # Derive all expected results before executing the agent artifact, then remove
    # the oracle so the submitted script cannot invoke or read it.
    for i in range(iterations):
        length = random.randint(min_len, max_len)
        payload = "".join(random.choice(printable_chars) for _ in range(length))
        try:
            oracle_result = subprocess.run(
                [ORACLE_BINARY, payload],
                capture_output=True,
                text=True,
                check=True
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i} with payload {repr(payload)}: {e.stderr}")
        cases.append((payload, oracle_result.stdout.strip()))

    os.unlink(ORACLE_BINARY)

    for i, (payload, oracle_output) in enumerate(cases):
        try:
            agent_result = subprocess.run(
                [AGENT_SCRIPT, payload],
                capture_output=True,
                text=True,
                check=True
            )
            agent_output = agent_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on iteration {i} with payload {repr(payload)}: {e.stderr}")

        assert agent_output == oracle_output, f"Mismatch on iteration {i}!\nPayload: {repr(payload)}\nOracle output: {oracle_output}\nAgent output: {agent_output}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
