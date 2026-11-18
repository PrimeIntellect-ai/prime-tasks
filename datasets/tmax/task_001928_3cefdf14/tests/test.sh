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

def test_makefile_fixed():
    makefile_path = "/app/fast-extractor-1.0/Makefile"
    assert os.path.isfile(makefile_path), f"File {makefile_path} does not exist."
    with open(makefile_path, 'r') as f:
        content = f.read()
    assert "-DMAX_LEN=1024" in content, "Makefile was not updated to set MAX_LEN=1024."

def test_fast_extract_binary_built_and_works():
    binary_path = "/app/fast-extractor-1.0/fast-extract"
    assert os.path.isfile(binary_path), f"Binary {binary_path} was not built."
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."

    # Test with input > 10 characters
    long_input = "A" * 50 + "\n"
    proc = subprocess.run([binary_path], input=long_input.encode('utf-8'), capture_output=True)
    assert proc.returncode == 0, f"fast-extract failed with long input. stderr: {proc.stderr.decode('utf-8', errors='replace')}"
    assert b"Success" in proc.stdout, "fast-extract did not output 'Success'."

def generate_random_windows1252_string(length):
    # alphanumeric + some windows-1252 special chars
    chars = string.ascii_letters + string.digits + "€ñáéíóú"
    return ''.join(random.choice(chars) for _ in range(length))

def generate_fuzz_input():
    num_lines = random.randint(10, 50)
    lines = []
    for _ in range(num_lines):
        num_fields = random.randint(3, 6)
        fields = []
        for i in range(num_fields):
            if i == 1 and random.random() < 0.3:
                fields.append("CRITICAL")
            else:
                fields.append(generate_random_windows1252_string(random.randint(2, 10)))
        lines.append(":".join(fields))

    text = "\n".join(lines) + "\n"
    return text.encode('windows-1252')

def test_transform_sh_fuzz_equivalence():
    agent_script = "/home/user/transform.sh"
    oracle_script = "/tests/transform_oracle.sh"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)

    for i in range(100):
        input_data = generate_fuzz_input()

        oracle_proc = subprocess.run(
            ["bash", oracle_script],
            input=input_data,
            capture_output=True
        )
        oracle_stdout = oracle_proc.stdout

        agent_proc = subprocess.run(
            ["bash", agent_script],
            input=input_data,
            capture_output=True
        )
        agent_stdout = agent_proc.stdout

        if oracle_stdout != agent_stdout:
            input_preview = input_data.decode('windows-1252', errors='replace')[:200]
            pytest.fail(
                f"Fuzz test failed on iteration {i}.\n"
                f"Input preview (Windows-1252 decoded):\n{input_preview}...\n"
                f"Expected output:\n{oracle_stdout.decode('utf-8', errors='replace')}\n"
                f"Agent output:\n{agent_stdout.decode('utf-8', errors='replace')}\n"
                f"Agent stderr:\n{agent_proc.stderr.decode('utf-8', errors='replace')}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
