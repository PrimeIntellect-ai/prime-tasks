#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import uuid

import pytest

CPP_FILE = "/home/user/tokenizer_check.cpp"
JSON_FILE = "/home/user/artifacts/token_summary.json"
RAW_DATA_DIR = "/home/user/artifacts/raw_data"
BINARY_FILE = f"/tmp/tokenizer_check_{uuid.uuid4().hex}"


def expected_counts():
    expected_files = 0
    expected_tokens = 0
    if os.path.isdir(RAW_DATA_DIR):
        for filename in os.listdir(RAW_DATA_DIR):
            if filename.endswith(".txt"):
                expected_files += 1
                filepath = os.path.join(RAW_DATA_DIR, filename)
                with open(filepath, "r") as f:
                    expected_tokens += len(f.read().split())
    return expected_tokens, expected_files


def load_and_check_output():
    assert os.path.isfile(JSON_FILE), f"The output JSON file {JSON_FILE} is missing."
    with open(JSON_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_FILE} does not contain valid JSON.")

    assert "total_tokens" in data, "The JSON output is missing the 'total_tokens' key."
    assert "num_files" in data, "The JSON output is missing the 'num_files' key."

    expected_tokens, expected_files = expected_counts()
    assert data["total_tokens"] == expected_tokens, \
        f"Expected {expected_tokens} total_tokens, but got {data['total_tokens']}."
    assert data["num_files"] == expected_files, \
        f"Expected {expected_files} num_files, but got {data['num_files']}."


def test_cpp_file_exists():
    """Check if the C++ source file was created."""
    assert os.path.isfile(CPP_FILE), f"The C++ source file {CPP_FILE} is missing."


def test_json_output_exists():
    """Check if the JSON summary file was created."""
    assert os.path.isfile(JSON_FILE), f"The output JSON file {JSON_FILE} is missing."


def test_json_output_contents():
    """Check if the existing JSON summary contains the correct counts."""
    load_and_check_output()


def test_cpp_compiles_and_generates_dynamic_output():
    """Compile the submitted source and exercise it on unpredictable inputs."""
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_FILE, "-o", BINARY_FILE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, \
        f"The C++ source failed to compile with C++17:\n{compile_result.stderr}"

    marker = uuid.uuid4().hex
    txt_one = os.path.join(RAW_DATA_DIR, f"verification_{marker}.txt")
    txt_two = os.path.join(RAW_DATA_DIR, f"verification_extra_{marker}.txt")
    ignored = os.path.join(RAW_DATA_DIR, f"verification_{marker}.csv")

    first_count = secrets.randbelow(7) + 4
    with open(txt_one, "w") as f:
        f.write(" \n\t".join(f"token_{uuid.uuid4().hex}" for _ in range(first_count)))
    with open(ignored, "w") as f:
        f.write(" ".join(f"ignored_{uuid.uuid4().hex}" for _ in range(23)))

    if os.path.exists(JSON_FILE):
        os.remove(JSON_FILE)
    run_result = subprocess.run(
        [BINARY_FILE], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert run_result.returncode == 0, \
        f"The compiled program exited with code {run_result.returncode}:\n{run_result.stderr}"
    load_and_check_output()

    second_count = secrets.randbelow(8) + 9
    with open(txt_one, "w") as f:
        f.write("\n".join(f"changed_{uuid.uuid4().hex}" for _ in range(second_count)))
    with open(txt_two, "w") as f:
        f.write("alpha\tbeta\n gamma   delta")

    os.remove(JSON_FILE)
    run_result = subprocess.run(
        [BINARY_FILE], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert run_result.returncode == 0, \
        f"The compiled program exited with code {run_result.returncode}:\n{run_result.stderr}"
    load_and_check_output()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
