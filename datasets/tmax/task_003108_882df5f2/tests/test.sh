#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess

def test_format_parser_exists_and_executable():
    """Check if the agent's script exists and is executable."""
    agent_script = "/home/user/format_parser.sh"
    assert os.path.isfile(agent_script), f"Missing script: {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Script is not executable: {agent_script}"

def test_fuzz_equivalence():
    """Fuzz test the agent's script against the oracle binary."""
    agent_script = "/home/user/format_parser.sh"
    oracle_script = "/tests/ref_parser"

    assert os.path.isfile(oracle_script), f"Missing oracle: {oracle_script}"
    assert os.access(oracle_script, os.X_OK), f"Oracle is not executable: {oracle_script}"

    # Generate 10000 random inputs
    random.seed(1337)
    inputs = []
    for _ in range(10000):
        c = random.random()
        if c < 0.1:
            # Invalid strings
            inputs.append("invalid_string_" + str(random.randint(0, 100)))
        elif c < 0.2:
            # Integers
            inputs.append(f"{random.randint(-1000, 1000)}")
        elif c < 0.3:
            # Standard floats
            inputs.append(f"{random.uniform(-1000, 1000):.2f}")
        elif c < 0.4:
            # Scientific notation
            inputs.append(f"{random.uniform(-100, 100):e}")
        elif c < 0.5:
            # Leading/trailing spaces
            inputs.append(f"  {random.uniform(-100, 100)}  ")
        elif c < 0.6:
            # Values that will exceed the clamp limit
            inputs.append(f"{random.uniform(999900, 1000100)}")
        elif c < 0.7:
            # Edge case floats
            inputs.append(random.choice([".5", "100.", "-.5", "-100."]))
        elif c < 0.8:
            # Empty or whitespace only
            inputs.append(random.choice(["", "   ", "\t"]))
        else:
            # General floats
            inputs.append(f"{random.uniform(-10000, 10000)}")

    input_str = "\n".join(inputs) + "\n"

    # Run Oracle
    oracle_proc = subprocess.run(
        [oracle_script],
        input=input_str,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, "Oracle script failed to execute"

    # Run Agent
    agent_proc = subprocess.run(
        [agent_script],
        input=input_str,
        text=True,
        capture_output=True
    )

    oracle_out = oracle_proc.stdout.splitlines()
    agent_out = agent_proc.stdout.splitlines()

    assert len(oracle_out) == len(inputs), f"Oracle output line count ({len(oracle_out)}) does not match input count ({len(inputs)})"
    assert len(agent_out) == len(inputs), f"Agent output line count ({len(agent_out)}) does not match input count ({len(inputs)})"

    for i, (inp, o_out, a_out) in enumerate(zip(inputs, oracle_out, agent_out)):
        assert o_out == a_out, (
            f"Mismatch on input {i}: {repr(inp)}\n"
            f"Expected (Oracle): {repr(o_out)}\n"
            f"Got (Agent):      {repr(a_out)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
