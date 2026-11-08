#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import pytest

def test_waf_script_exists_and_executable():
    """Test that the agent's WAF script exists and is executable."""
    script_path = "/home/user/waf.sh"
    assert os.path.isfile(script_path), f"Missing WAF script at {script_path}"
    assert os.access(script_path, os.X_OK), f"WAF script at {script_path} is not executable"

def test_fuzz_equivalence():
    """Test that the agent's script is bit-exact equivalent to the oracle on random inputs."""
    oracle_path = "/tests/waf_oracle"
    agent_path = "/home/user/waf.sh"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent script missing at {agent_path}"

    random.seed(42)

    # Base characters: printable ASCII without control characters other than space
    chars = string.ascii_letters + string.digits + string.punctuation + " "

    inputs = []

    # Generate 1000 random strings
    for _ in range(1000):
        length = random.randint(1, 200)
        s = "".join(random.choice(chars) for _ in range(length))

        # Inject edge cases occasionally to ensure specific rules are triggered
        prob = random.random()
        if prob < 0.1:
            # Inject DROP TABLE (various cases)
            case_variant = "".join(random.choice([c.upper(), c.lower()]) for c in "DROP TABLE")
            insert_pos = random.randint(0, len(s))
            s = s[:insert_pos] + case_variant + s[insert_pos:]
        elif prob < 0.2:
            # Inject <svg onload (various cases)
            case_variant = "".join(random.choice([c.upper(), c.lower()]) for c in "<svg onload")
            insert_pos = random.randint(0, len(s))
            s = s[:insert_pos] + case_variant + s[insert_pos:]
        elif prob < 0.3:
            # Inject backticks
            s += "`" * random.randint(1, 5)
        elif prob < 0.4:
            # Inject multiple spaces
            s += "   " * random.randint(1, 3)

        # Truncate to 200 if exceeded
        s = s[:200]
        if not s:
            s = "a"
        inputs.append(s)

    # Add empty string as an edge case
    inputs.append("")

    for idx, inp in enumerate(inputs):
        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_path, inp],
                capture_output=True,
                text=True,
                timeout=2
            )
            oracle_stdout = oracle_proc.stdout
            oracle_returncode = oracle_proc.returncode
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {idx}: {repr(inp)}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                [agent_path, inp],
                capture_output=True,
                text=True,
                timeout=2
            )
            agent_stdout = agent_proc.stdout
            agent_returncode = agent_proc.returncode
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {idx}: {repr(inp)}")

        # Compare
        assert agent_returncode == oracle_returncode, \
            f"Exit code mismatch on input {idx}: {repr(inp)}. Oracle: {oracle_returncode}, Agent: {agent_returncode}"

        assert agent_stdout == oracle_stdout, \
            f"Output mismatch on input {idx}: {repr(inp)}.\nOracle output:\n{repr(oracle_stdout)}\nAgent output:\n{repr(agent_stdout)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
