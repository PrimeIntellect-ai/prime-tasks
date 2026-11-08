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

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_aligner.py"
    agent_path = "/home/user/aligner.py"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent script missing at {agent_path}"

    random.seed(42)

    for i in range(200):
        num_words = random.randint(0, 50)
        words = []
        for _ in range(num_words):
            word_len = random.randint(1, 10)
            word = ''.join(random.choices(string.ascii_uppercase, k=word_len))
            words.append(word)

        input_text = " ".join(words)

        # Run oracle
        oracle_proc = subprocess.run(
            ["python3", oracle_path],
            input=input_text,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input: {input_text}\nStderr: {oracle_proc.stderr}"

        # Run agent
        agent_proc = subprocess.run(
            ["python3", agent_path],
            input=input_text,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent script crashed on input: '{input_text}'\nError: {agent_proc.stderr}"

        oracle_out = oracle_proc.stdout
        agent_out = agent_proc.stdout

        assert oracle_out == agent_out, (
            f"Mismatch on input: '{input_text}'\n"
            f"Expected (Oracle):\n{oracle_out}\n"
            f"Got (Agent):\n{agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
