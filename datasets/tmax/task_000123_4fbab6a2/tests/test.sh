#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import json
import random
import string
import pytest

def test_vendored_package_compiles():
    """Verify that the vendored package compiles successfully."""
    make_result = subprocess.run(
        ["make", "-C", "/app/vendored/csv_parser"],
        capture_output=True,
        text=True
    )
    assert make_result.returncode == 0, f"Compilation of vendored package failed:\n{make_result.stderr}"
    assert os.path.isfile("/app/vendored/csv_parser/libcsvparser.a"), "libcsvparser.a was not built."

def test_agent_executable_exists():
    """Verify that the agent's executable exists and is executable."""
    executable_path = "/home/user/src/manifest_filter"
    assert os.path.isfile(executable_path), f"Executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."

def generate_random_csv(num_lines):
    lines = []
    file_types = ["log", "db", "txt", "bin"]
    for _ in range(num_lines):
        # Generate random filename
        length = random.randint(5, 20)
        filename = "/" + "".join(random.choices(string.ascii_letters + string.digits, k=length))

        # Generate random size
        # Include edge cases: exactly 10485760
        if random.random() < 0.05:
            size_bytes = 10485760
        else:
            size_bytes = random.randint(0, 100000000)

        file_type = random.choice(file_types)
        lines.append(f"{filename},{size_bytes},{file_type}")

    csv_data = "\n".join(lines)
    # Occasionally omit trailing newline
    if lines and random.random() < 0.5:
        csv_data += "\n"

    return csv_data

def run_binary(binary_path, input_data):
    result = subprocess.run(
        [binary_path],
        input=input_data,
        capture_output=True,
        text=True,
        timeout=5
    )
    return result

def test_fuzz_equivalence():
    """Run fuzz equivalence testing between agent and oracle."""
    agent_bin = "/home/user/src/manifest_filter"
    oracle_bin = "/opt/oracle/manifest_filter_oracle"

    assert os.path.isfile(oracle_bin), f"Oracle binary {oracle_bin} not found."
    assert os.path.isfile(agent_bin), f"Agent binary {agent_bin} not found."

    random.seed(42)
    N = 500

    for i in range(N):
        num_lines = random.randint(0, 1000)
        csv_input = generate_random_csv(num_lines)

        oracle_res = run_binary(oracle_bin, csv_input)
        agent_res = run_binary(agent_bin, csv_input)

        assert oracle_res.returncode == 0, f"Oracle failed on input {i}"

        if agent_res.returncode != 0:
            pytest.fail(f"Agent binary failed (exit code {agent_res.returncode}) on input:\n{csv_input}\nStderr: {agent_res.stderr}")

        try:
            oracle_json = json.loads(oracle_res.stdout)
        except json.JSONDecodeError:
            oracle_json = [] # Fallback if oracle outputs empty or invalid, though oracle should be bug-free

        try:
            agent_json = json.loads(agent_res.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent binary produced invalid JSON on input:\n{csv_input}\nStdout: {agent_res.stdout}")

        if oracle_json != agent_json:
            pytest.fail(
                f"Mismatch on input {i}!\n"
                f"Input CSV:\n{csv_input}\n"
                f"Expected JSON (Oracle):\n{json.dumps(oracle_json, indent=2)}\n"
                f"Actual JSON (Agent):\n{json.dumps(agent_json, indent=2)}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
