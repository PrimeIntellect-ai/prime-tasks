#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import secrets
import subprocess
import sys

def test_calc_token_exists():
    path = "/home/user/.calc_token"
    assert os.path.exists(path), f"The required hidden file {path} was not created."

def test_process_py_exists():
    path = "/home/user/process.py"
    assert os.path.isfile(path), f"The Python script {path} was not created."

def test_final_csv_correct():
    input_path = "/home/user/input.csv"
    final_path = "/home/user/final.csv"

    assert os.path.isfile(final_path), f"The final output file {final_path} was not created."

    with open(input_path, 'r') as f:
        reader = csv.reader(f)
        input_rows = list(reader)

    assert len(input_rows) > 1, f"{input_path} is empty or missing data."
    header = input_rows[0]
    assert header == ['x'], f"Unexpected header in {input_path}."

    expected_rows = [['x', 'y']]
    for row in input_rows[1:]:
        x = int(row[0].strip())
        y = 3 * (x ** 2) + 2 * x + 1
        expected_rows.append([str(x), str(y)])

    with open(final_path, 'r') as f:
        reader = csv.reader(f)
        final_rows = list(reader)

    assert len(final_rows) == len(expected_rows), f"{final_path} does not have the expected number of rows."

    for i, (expected, actual) in enumerate(zip(expected_rows, final_rows)):
        assert actual == expected, f"Row {i+1} in {final_path} is incorrect. Expected {expected}, got {actual}."

def test_output_csv_exists():
    path = "/home/user/output.csv"
    assert os.path.isfile(path), f"The intermediate file {path} was not generated. Did you run legacy_bin?"

def test_process_py_executes_on_fresh_input():
    process_path = "/home/user/process.py"
    input_path = "/home/user/input.csv"
    final_path = "/home/user/final.csv"

    assert os.path.isfile(process_path), f"The Python script {process_path} was not created."

    with open(input_path, "rb") as f:
        original_input = f.read()
    original_final = None
    if os.path.exists(final_path):
        with open(final_path, "rb") as f:
            original_final = f.read()

    values = [-17, 0, 23]
    while len(values) < 10:
        candidate = secrets.randbelow(200001) - 100000
        if candidate not in values and candidate not in range(1, 16):
            values.append(candidate)

    try:
        with open(input_path, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["x"])
            for x in values:
                writer.writerow([x])

        if os.path.exists(final_path):
            os.remove(final_path)

        result = subprocess.run(
            [sys.executable, process_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"{process_path} failed when executed (exit {result.returncode}). "
            f"stderr: {result.stderr}"
        )
        assert os.path.isfile(final_path), f"{process_path} did not create {final_path}."

        with open(final_path, "r", newline="") as f:
            actual_rows = list(csv.reader(f))

        expected_rows = [["x", "y"]]
        expected_rows.extend(
            [[str(x), str(3 * (x ** 2) + 2 * x + 1)] for x in values]
        )
        assert actual_rows == expected_rows, (
            f"{process_path} did not correctly transform a fresh input. "
            f"Expected {expected_rows}, got {actual_rows}."
        )
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
        if original_final is None:
            if os.path.exists(final_path):
                os.remove(final_path)
        else:
            with open(final_path, "wb") as f:
                f.write(original_final)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
