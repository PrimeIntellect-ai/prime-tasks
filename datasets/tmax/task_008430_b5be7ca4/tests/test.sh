#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import math
import os
import re
import secrets
import stat
import subprocess
import tempfile
import pytest


def test_phase1_token():
    dump_path = "/home/user/dump.bin"
    token_path = "/home/user/token.txt"

    assert os.path.isfile(dump_path), f"File {dump_path} is missing."
    assert os.path.isfile(token_path), f"File {token_path} is missing. Did you save the extracted token?"

    # Extract the true token from the dump
    with open(dump_path, 'rb') as f:
        dump_data = f.read()

    match = re.search(b'RECOVERY_TOKEN_[0-9a-f]+', dump_data)
    assert match is not None, "Could not find RECOVERY_TOKEN_ in dump.bin (test environment issue)"
    expected_token = match.group(0).decode('ascii')

    with open(token_path, 'r') as f:
        actual_token = f.read().strip()

    assert actual_token == expected_token, f"Token in {token_path} is incorrect. Expected {expected_token}, got {actual_token}."


def test_phase2_failing_row():
    data_path = "/home/user/app/data.csv"
    failing_row_path = "/home/user/failing_row.csv"

    assert os.path.isfile(data_path), f"File {data_path} is missing."
    assert os.path.isfile(failing_row_path), f"File {failing_row_path} is missing. Did you save the failing row?"

    # Find the failing row in data.csv (the one with 14.5000000)
    expected_row = None
    with open(data_path, 'r') as f:
        for line in f:
            if "14.5" in line:
                expected_row = line.strip()
                break

    assert expected_row is not None, "Could not find the failing row in data.csv (test environment issue)"

    with open(failing_row_path, 'r') as f:
        actual_row = f.read().strip()

    assert actual_row == expected_row, f"Failing row in {failing_row_path} is incorrect. Expected {expected_row}, got {actual_row}."


def run_processor(binary_path, data_path):
    completed = subprocess.run(
        [binary_path, data_path],
        cwd="/home/user/app",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"The repaired processor failed for {data_path} with exit code "
        f"{completed.returncode}: {completed.stderr}"
    )
    return completed.stdout.strip()


def test_phase3_result():
    app_path = "/home/user/app"
    source_path = "/home/user/app/main.go"
    data_path = "/home/user/app/data.csv"
    result_path = "/home/user/result.txt"

    assert os.path.isfile(data_path), f"File {data_path} is missing."
    assert os.path.isfile(result_path), f"File {result_path} is missing. Did you save the final result?"

    # Compute the expected result
    total = 0.0
    with open(data_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            if len(parts) == 2:
                val = float(parts[1])
                total += math.sqrt(val)

    expected_result = f"{total:.4f}"

    with open(result_path, 'r') as f:
        actual_result = f.read().strip()

    assert actual_result == expected_result, f"Result in {result_path} is incorrect. Expected {expected_result}, got {actual_result}."

    # The requested Go artifact must exist as a real source file and compile.
    assert os.path.isfile(source_path), f"File {source_path} is missing."
    assert stat.S_ISREG(os.lstat(source_path).st_mode), f"File {source_path} must be a regular file."

    with tempfile.TemporaryDirectory(prefix="verify_processor_") as temp_dir:
        binary_path = os.path.join(temp_dir, "processor")
        build = subprocess.run(
            ["go", "build", "-o", binary_path, "main.go"],
            cwd=app_path,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert build.returncode == 0, f"main.go does not compile: {build.stderr}"
        assert os.path.isfile(binary_path), "go build did not produce an executable."

        # Run the submitted program on the full incident dataset and ensure the
        # saved result is its actual successful standard output.
        full_output = run_processor(binary_path, data_path)
        assert full_output == expected_result, (
            f"The repaired processor produced {full_output!r} on data.csv; "
            f"expected {expected_result!r}."
        )
        assert full_output == actual_result, (
            "result.txt is not the standard output of the repaired processor "
            "running on the full data.csv."
        )

        # Exercise the compiled repair on a fresh dataset whose aggregate is
        # derived at verification time. Including 14.5 verifies that the
        # original float32 convergence panic has actually been repaired.
        value_strings = ["14.5000000"]
        for _ in range(40):
            scaled = 250000 + secrets.randbelow(99750001)
            value_strings.append(f"{scaled / 1000000.0:.7f}")

        generated_path = os.path.join(temp_dir, "generated.csv")
        with open(generated_path, "w") as f:
            for value in value_strings:
                f.write(f"metric_x,{value}\n")

        generated_expected = f"{sum(math.sqrt(float(v)) for v in value_strings):.4f}"
        generated_output = run_processor(binary_path, generated_path)
        assert generated_output == generated_expected, (
            f"The repaired processor produced {generated_output!r} on a fresh "
            f"dataset; expected {generated_expected!r}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
