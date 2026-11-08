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

def generate_random_input():
    length = random.randint(10, 1000)
    chars = string.printable.replace('\r', '') # avoid carriage return issues

    # ensure we have some repeated characters
    result = []
    while len(result) < length:
        if random.random() < 0.1:
            # insert repeated char
            char = random.choice(chars)
            count = random.randint(3, 15)
            result.extend([char] * count)
        elif random.random() < 0.05:
            # insert dictionary words
            word = random.choice(["LEGACY_SYSTEM", "TEMP_VAR"])
            result.extend(list(word))
        else:
            result.append(random.choice(chars))

    # randomly add newlines to test line numbering
    for _ in range(random.randint(0, 10)):
        if len(result) > 0:
            idx = random.randint(0, len(result) - 1)
            result[idx] = '\n'

    return "".join(result)[:length]

def test_process_doc_fuzz_equivalence():
    agent_script = "/home/user/process_doc.sh"
    oracle_script = "/tests/oracle_process"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)

    for i in range(50):
        test_input = generate_random_input()

        # Run oracle uploaded only at verification time
        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=test_input,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"
        oracle_output = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            ["/bin/bash", agent_script],
            input=test_input,
            text=True,
            capture_output=True
        )

        agent_output = agent_proc.stdout

        if agent_output != oracle_output:
            error_msg = (
                f"Mismatch on iteration {i}.\n\n"
                f"INPUT:\n{repr(test_input)}\n\n"
                f"EXPECTED (Oracle):\n{repr(oracle_output)}\n\n"
                f"ACTUAL (Agent):\n{repr(agent_output)}\n\n"
                f"Agent STDERR:\n{agent_proc.stderr}"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
