#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_extracted_bits():
    extracted_path = "/app/extracted_bits.txt"
    assert os.path.isfile(extracted_path), f"File {extracted_path} does not exist."

    with open(extracted_path, "r") as f:
        content = f.read().strip()

    expected_bits = "01001000011001010110110001101100011011110010000001010111011011110111001001101100011001000010000100000000"
    assert content == expected_bits, f"Extracted bits do not match the expected sequence. Got {content}"

def test_fuzz_equivalence():
    agent_script = "/app/diag_tools/decode.py"
    oracle_script = "/tests/decode_oracle.py"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}"

    random.seed(42)
    N = 200

    for _ in range(N):
        length = random.randint(16, 1024)
        input_str = "".join(random.choices(["0", "1"], k=length))

        agent_cmd = ["python3", agent_script, input_str]
        oracle_cmd = ["python3", oracle_script, input_str]

        try:
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, timeout=2)
            agent_out = agent_res.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: {input_str}")

        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, timeout=2)
            oracle_out = oracle_res.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle script timed out on input: {input_str}")

        assert agent_res.returncode == oracle_res.returncode, f"Return code mismatch on input {input_str}. Agent: {agent_res.returncode}, Oracle: {oracle_res.returncode}"
        assert agent_out == oracle_out, f"Output mismatch on input {input_str}.\nAgent output: {agent_out!r}\nOracle output: {oracle_out!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
