#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/calculate_metrics.sh"
CSV_PATH = "/home/user/traffic_logs.csv"
SCALE = 10000000000000000


def test_final_metric_file():
    file_path = "/home/user/final_metric.txt"
    assert os.path.exists(file_path), f"File missing: {file_path}"
    assert os.path.isfile(file_path), f"Not a file: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_value = "11500000000000000000"
    assert content == expected_value, f"Expected {expected_value} in {file_path}, but got {content}"


def test_script_execution():
    script_path = SCRIPT_PATH
    assert os.path.exists(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

    try:
        result = subprocess.run([script_path], capture_output=True, text=True, check=True)
        output = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script execution failed with error: {e.stderr}")

    expected_value = "11500000000000000000"
    lines = [line for line in output.split('\n') if line.strip()]
    assert lines, "Script produced no output"
    assert lines[-1] == expected_value, f"Expected script to output {expected_value}, but got {lines[-1]}"


def test_script_is_bash_wrapper_and_processes_csv_dynamically():
    assert os.path.isfile(SCRIPT_PATH), f"Not a regular file: {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "r", errors="replace") as f:
        first_line = f.readline().strip()
    assert re.fullmatch(r"#!(?:/bin/bash|/usr/bin/bash|/usr/bin/env bash)", first_line), \
        "calculate_metrics.sh must remain a Bash script"

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    rng = secrets.SystemRandom()
    cases = [
        [rng.randrange(1000, 10000) for _ in range(7)],
        [rng.randrange(100000, 1000000) for _ in range(11)],
    ]

    try:
        for case_number, byte_values in enumerate(cases, 1):
            with open(CSV_PATH, "w", newline="") as f:
                f.write("id,bytes\n")
                for packet_id, byte_count in enumerate(byte_values, 1):
                    f.write(f"{packet_id},{byte_count}\n")

            expected_value = str(sum(value * SCALE for value in byte_values))
            result = subprocess.run(
                [SCRIPT_PATH], capture_output=True, text=True, timeout=10
            )
            assert result.returncode == 0, \
                f"Script failed on generated case {case_number}: {result.stderr}"
            lines = [line for line in result.stdout.split("\n") if line.strip()]
            assert lines, f"Script produced no output on generated case {case_number}"
            assert lines[-1] == expected_value, \
                f"Generated case {case_number}: expected {expected_value}, got {lines[-1]}"
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
