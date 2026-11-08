#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import statistics
import subprocess
import sys

import pytest


def test_00_original_transaction_inputs_are_present_and_unchanged():
    directory = "/home/user/transactions"
    expected = {
        "batch_1.csv": ["10.0", "12.0", "14.0", "16.0", "18.0"],
        "batch_2.csv": ["1000000001.0", "1000000002.0", "1000000003.0", "1000000004.0", "1000000005.0"],
        "batch_3.csv": ["100000000.1", "100000000.2", "100000000.15", "100000000.1", "100000000.2"],
    }
    assert os.path.isdir(directory), f"Directory {directory} is missing."
    actual_csvs = sorted(f for f in os.listdir(directory) if f.endswith(".csv"))
    assert actual_csvs == sorted(expected), "The supplied transaction batch files were removed or changed."
    for filename, expected_lines in expected.items():
        with open(os.path.join(directory, filename)) as file:
            actual_lines = [line.strip() for line in file if line.strip()]
        assert actual_lines == expected_lines, f"The supplied input {filename} was changed."


def test_fixed_results_exists_and_correct():
    results_file = "/home/user/fixed_results.txt"
    assert os.path.isfile(results_file), f"File {results_file} is missing. Did you save the output?"

    directory = "/home/user/transactions"
    assert os.path.isdir(directory), f"Directory {directory} is missing."

    expected_lines = []
    for f in sorted(os.listdir(directory)):
        if f.endswith('.csv'):
            with open(os.path.join(directory, f)) as file:
                values = [float(line.strip()) for line in file if line.strip()]
                if len(values) > 1:
                    std_dev = statistics.stdev(values)
                else:
                    std_dev = 0.0
                expected_lines.append(f"{f},{std_dev:.4f}")

    with open(results_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {results_file} are incorrect.\n"
        f"Expected:\n{expected_lines}\n"
        f"Got:\n{actual_lines}"
    )


def test_fixed_script_executes_and_is_numerically_stable(tmp_path):
    script = "/home/user/aggregate_transactions.py"
    assert os.path.isfile(script), f"File {script} is missing."

    input_dir = tmp_path / ("transactions_" + secrets.token_hex(8))
    input_dir.mkdir()

    base = 1_000_000_000_000 + secrets.randbelow(8_000_000_000_000)
    shift = secrets.randbelow(101) - 50
    batches = {
        "large_" + secrets.token_hex(5) + ".csv": [
            float(base + shift + offset) for offset in (-2, -1, 0, 1, 2)
        ],
        "ordinary_" + secrets.token_hex(5) + ".csv": [
            3.25, 7.5, -2.0, 11.125, 4.75
        ],
        "single_" + secrets.token_hex(5) + ".csv": [float(base + 123)],
    }

    for filename, values in batches.items():
        with open(input_dir / filename, "w") as file:
            for value in values:
                file.write(repr(value) + "\n")

    expected_lines = []
    for filename in sorted(batches):
        with open(input_dir / filename) as file:
            parsed = [float(line.strip()) for line in file if line.strip()]
        std_dev = statistics.stdev(parsed) if len(parsed) > 1 else 0.0
        expected_lines.append(f"{filename},{std_dev:.4f}")

    completed = subprocess.run(
        [sys.executable, script, str(input_dir)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"The fixed script failed on valid transaction data.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    actual_lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    assert actual_lines == expected_lines, (
        "The script does not calculate stable sample standard deviations.\n"
        f"Expected: {expected_lines}\nGot: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
