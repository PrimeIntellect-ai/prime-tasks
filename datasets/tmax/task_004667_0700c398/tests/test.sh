#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import re
import secrets
import string
import subprocess
import sys
import pytest

INPUT_CSV = "/home/user/data/input.csv"
OUTPUT_DIR = "/home/user/output"
HOURLY_ERRORS_FILE = os.path.join(OUTPUT_DIR, "hourly_errors.json")
CHECKPOINT_FILE = os.path.join(OUTPUT_DIR, "checkpoint.json")
SCRIPT_FILE = "/home/user/etl_pipeline.py"
CHECKPOINT_KEYS = {
    "total_logical_rows",
    "error_rows_found",
    "extracted_codes_count",
}


def compute_results(input_csv):
    if not os.path.exists(input_csv):
        pytest.fail(f"Input file {input_csv} is missing.")

    total_logical_rows = 0
    error_rows_found = 0
    extracted_codes_count = 0
    hourly_errors = {}
    code_pattern = re.compile(r"ErrorCode:\s*([A-Z]{3}-\d{4})")

    with open(input_csv, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            if not row or len(row) < 3:
                continue
            total_logical_rows += 1
            timestamp, level, message = row[0], row[1], row[2]
            if level == "ERROR":
                error_rows_found += 1
                match = code_pattern.search(message)
                if match:
                    extracted_codes_count += 1
                    code = match.group(1)
                    bucket = timestamp[:13]
                    hourly_errors.setdefault(bucket, {})
                    hourly_errors[bucket][code] = hourly_errors[bucket].get(code, 0) + 1

    return {
        "checkpoint": {
            "total_logical_rows": total_logical_rows,
            "error_rows_found": error_rows_found,
            "extracted_codes_count": extracted_codes_count,
        },
        "hourly_errors": hourly_errors,
    }


def compute_expected_results():
    return compute_results(INPUT_CSV)


def run_script():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for path in (HOURLY_ERRORS_FILE, CHECKPOINT_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    return subprocess.run(
        [sys.executable, SCRIPT_FILE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture(scope="session", autouse=True)
def execute_submission_on_original_input():
    assert os.path.exists(SCRIPT_FILE), f"The script {SCRIPT_FILE} does not exist."
    assert os.path.isfile(SCRIPT_FILE), f"The path {SCRIPT_FILE} is not a file."
    result = run_script()
    assert result.returncode == 0, (
        f"{SCRIPT_FILE} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_script_exists():
    assert os.path.exists(SCRIPT_FILE), f"The script {SCRIPT_FILE} does not exist."
    assert os.path.isfile(SCRIPT_FILE), f"The path {SCRIPT_FILE} is not a file."


def test_output_files_exist():
    assert os.path.exists(HOURLY_ERRORS_FILE), f"Output file {HOURLY_ERRORS_FILE} does not exist."
    assert os.path.exists(CHECKPOINT_FILE), f"Output file {CHECKPOINT_FILE} does not exist."


def test_checkpoint_contents():
    expected = compute_expected_results()["checkpoint"]

    try:
        with open(CHECKPOINT_FILE, "r", encoding="utf-8") as f:
            actual = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {CHECKPOINT_FILE} is not valid JSON.")

    assert isinstance(actual, dict), f"{CHECKPOINT_FILE} must contain a JSON object."
    assert set(actual.keys()) == CHECKPOINT_KEYS, (
        f"{CHECKPOINT_FILE} must contain exactly the required checkpoint keys."
    )
    for key in ["total_logical_rows", "error_rows_found", "extracted_codes_count"]:
        assert key in actual, f"Key '{key}' is missing from {CHECKPOINT_FILE}."
        assert type(actual[key]) is int, f"Value for '{key}' must be an integer."
        assert actual[key] == expected[key], f"Expected {key} to be {expected[key]}, but got {actual[key]}."


def test_hourly_errors_contents():
    expected = compute_expected_results()["hourly_errors"]

    try:
        with open(HOURLY_ERRORS_FILE, "r", encoding="utf-8") as f:
            actual = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {HOURLY_ERRORS_FILE} is not valid JSON.")

    assert actual == expected, f"Hourly errors JSON does not match expected output.\nExpected: {expected}\nActual: {actual}"


def test_pipeline_behavior_on_alternate_multiline_input():
    alphabet = string.ascii_uppercase

    def new_code():
        return "".join(secrets.choice(alphabet) for _ in range(3)) + "-" + "".join(
            secrets.choice(string.digits) for _ in range(4)
        )

    codes = []
    while len(codes) < 3:
        candidate = new_code()
        if candidate not in codes:
            codes.append(candidate)
    code_a, code_b, code_c = codes

    rows = [
        ["timestamp", "level", "message"],
        ["2025-07-03T08:01:02Z", "INFO", f"Informational line\nErrorCode: {code_c}"],
        ["2025-07-03T08:10:00Z", "ERROR", f"First line\nSecond line\nErrorCode: {code_a}\nTail"],
        ["2025-07-03T08:20:00Z", "ERROR", f"Failure\nErrorCode:\t{code_b}"],
        ["2025-07-03T08:30:00Z", "ERROR", "Failure without a valid code\nStill an error"],
        ["2025-07-03T08:40:00Z", "ERROR", f"ErrorCode:{code_a}\nErrorCode: {code_c}"],
        ["2025-07-03T08:50:00Z", "WARN", f"ErrorCode: {code_b}"],
        ["2025-07-03T08:55:00Z", "error", f"ErrorCode: {code_c}"],
        ["2025-07-03T09:00:00Z", "ERROR", f"Multiline\nmessage\nErrorCode: {code_c}"],
        ["2025-07-03T09:05:00Z", "DEBUG", "Debug text\nwith another line"],
    ]

    with open(INPUT_CSV, "rb") as f:
        original_input = f.read()

    alternate_actual = None
    alternate_expected = None
    alternate_result = None
    restore_result = None
    try:
        with open(INPUT_CSV, "w", encoding="utf-8", newline="") as f:
            csv.writer(f).writerows(rows)

        alternate_expected = compute_results(INPUT_CSV)
        alternate_result = run_script()
        assert alternate_result.returncode == 0, (
            f"Script failed on alternate input with status {alternate_result.returncode}.\n"
            f"stdout:\n{alternate_result.stdout}\nstderr:\n{alternate_result.stderr}"
        )
        assert os.path.isfile(HOURLY_ERRORS_FILE), "Alternate run did not create hourly_errors.json."
        assert os.path.isfile(CHECKPOINT_FILE), "Alternate run did not create checkpoint.json."
        alternate_actual = {
            "hourly_errors": load_json(HOURLY_ERRORS_FILE),
            "checkpoint": load_json(CHECKPOINT_FILE),
        }
    finally:
        with open(INPUT_CSV, "wb") as f:
            f.write(original_input)
        restore_result = run_script()

    assert restore_result.returncode == 0, (
        f"Script failed when rerun on the restored original input.\n"
        f"stdout:\n{restore_result.stdout}\nstderr:\n{restore_result.stderr}"
    )
    assert isinstance(alternate_actual["checkpoint"], dict)
    assert set(alternate_actual["checkpoint"].keys()) == CHECKPOINT_KEYS
    for key in CHECKPOINT_KEYS:
        assert type(alternate_actual["checkpoint"][key]) is int
    assert alternate_actual["checkpoint"] == alternate_expected["checkpoint"]
    assert alternate_actual["hourly_errors"] == alternate_expected["hourly_errors"]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
