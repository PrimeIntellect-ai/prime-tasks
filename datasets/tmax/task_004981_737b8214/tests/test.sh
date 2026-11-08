#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def generate_fuzz_inputs(n=1000, seed=42):
    random.seed(seed)
    inputs = ["", "     ", "missing", "123", "missing 123"]
    vocab = ["missing", "NaN", "word", "hello", "test", "foo", "bar", "12a", "a12", "special!@#"]
    vocab += [str(i) for i in range(50)]

    for _ in range(n - len(inputs)):
        length = random.randint(0, 200)
        if length == 0:
            inputs.append("")
            continue

        words = []
        while sum(len(w) for w in words) + len(words) < length:
            words.append(random.choice(vocab))

        res = ""
        for w in words:
            res += " " * random.randint(1, 3) + w
        res += " " * random.randint(0, 3)
        inputs.append(res[:200])

    return inputs

def test_tokenizer_equivalence():
    agent_script = "/home/user/tokenizer.sh"
    oracle_script = "/tests/oracle_tokenizer.sh"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script at {agent_script} is not executable"
    assert os.path.isfile(oracle_script), f"Test oracle missing at {oracle_script}"

    inputs = generate_fuzz_inputs(1000)

    for i, inp in enumerate(inputs):
        oracle_res = subprocess.run(["bash", oracle_script, inp], capture_output=True, text=True)
        agent_res = subprocess.run([agent_script, inp], capture_output=True, text=True)

        assert agent_res.stdout == oracle_res.stdout, (
            f"Mismatch on input {i}:\n"
            f"Input: {repr(inp)}\n"
            f"Oracle output:\n{repr(oracle_res.stdout)}\n"
            f"Agent output:\n{repr(agent_res.stdout)}\n"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
