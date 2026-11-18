#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest


def test_fixed_decoder_exists_and_executable():
    path = "/home/user/fixed_decoder.sh"
    assert os.path.isfile(path), f"Missing fixed decoder script at {path}"
    assert os.access(path, os.X_OK), f"Fixed decoder at {path} is not executable"


def generate_random_input(force_zero=False):
    num_blocks = random.randint(1, 5)
    hex_chars = "0123456789ABCDEF"
    result = ""
    for i in range(num_blocks):
        if force_zero and i == 0:
            count_hex = "00"
        else:
            count_hex = random.choice(hex_chars) + random.choice(hex_chars)
        char_hex = random.choice("4567") + random.choice(hex_chars)
        result += count_hex + char_hex
    return result


def expected_decode(payload):
    output = []
    for i in range(0, len(payload), 4):
        count = int(payload[i:i + 2], 16)
        if count == 0:
            count = 256
        char = chr(int(payload[i + 2:i + 4], 16))
        output.append(char * count)
    return "".join(output)


def test_fuzz_equivalence():
    agent_path = "/home/user/fixed_decoder.sh"
    assert os.path.isfile(agent_path), f"Agent decoder missing at {agent_path}"

    random.seed(42)
    iterations = 50

    for i in range(iterations):
        force_zero = (i % 5 == 0)
        test_input = generate_random_input(force_zero=force_zero)
        expected_output = expected_decode(test_input)

        try:
            agent_proc = subprocess.run(
                [agent_path, test_input],
                capture_output=True,
                text=True,
                timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out (possible infinite loop) on input: {test_input}")

        assert agent_proc.returncode == 0, \
            f"Unexpected return code on input {test_input}: {agent_proc.returncode}"
        assert agent_proc.stdout == expected_output, \
            f"Output mismatch on input {test_input}.\nExpected: {repr(expected_output)}\nGot: {repr(agent_proc.stdout)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
