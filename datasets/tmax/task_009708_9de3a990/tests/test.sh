#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess

import pytest

PROJECT_DIR = "/home/user/project"
PROCESS_FILE = os.path.join(PROJECT_DIR, "process.py")
DATA_FILE = os.path.join(PROJECT_DIR, "data.jsonl")
RESULTS_FILE = os.path.join(PROJECT_DIR, "results.jsonl")


def run_process():
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    completed = subprocess.run(
        ["python3", PROCESS_FILE],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"process.py failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS_FILE), f"Expected output file {RESULTS_FILE} does not exist."


def read_strict_results():
    records = []
    with open(RESULTS_FILE, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            assert line, f"Blank line found at line {line_num} in {RESULTS_FILE}"
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {RESULTS_FILE} is not valid JSON: {line}")
            assert isinstance(record, dict), f"Line {line_num} is not a JSON object"
            assert set(record) == {"id", "cube_root"}, (
                f"Line {line_num} must contain exactly the keys 'id' and 'cube_root'"
            )
            records.append(record)
    return records


def test_00_process_script_executes_on_unseen_utf8_data():
    assert os.path.isfile(PROCESS_FILE), f"Expected Python script {PROCESS_FILE} does not exist."
    assert not os.path.islink(PROCESS_FILE), f"Expected {PROCESS_FILE} to be a regular submitted script."
    with open(PROCESS_FILE, "r", encoding="utf-8") as f:
        compile(f.read(), PROCESS_FILE, "exec")

    with open(DATA_FILE, "rb") as f:
        original_data = f.read()

    root = secrets.randbelow(20) + 3
    values = [
        (secrets.randbelow(19801) + 200) / 100.0,
        float(root ** 3),
        (secrets.randbelow(9801) + 200) / 100.0,
        (secrets.randbelow(19801) + 200) / 100.0,
    ]
    ids = [f"verify-{secrets.token_hex(8)}" for _ in values]
    inputs = [
        {"id": ids[0], "value": values[0], "meta": "UTF-8 em-dash — and café"},
        {"id": ids[1], "value": str(int(values[1]))},
        {"id": ids[2], "value": values[2]},
        {"id": ids[3], "value": str(values[3]), "meta": "snowman ☃"},
    ]

    try:
        with open(DATA_FILE, "w", encoding="utf-8") as f:
            for record in inputs:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")

        run_process()
        records = read_strict_results()
        assert len(records) == len(inputs), f"Expected {len(inputs)} records, found {len(records)}"

        actual = {}
        for record in records:
            assert record["id"] not in actual, f"Duplicate output ID: {record['id']}"
            value = record["cube_root"]
            assert isinstance(value, (int, float)) and not isinstance(value, bool), (
                f"cube_root for {record['id']} is not numeric: {value}"
            )
            actual[record["id"]] = value

        assert set(actual) == set(ids), "Output IDs do not match the input IDs"
        for record, numeric_value in zip(inputs, values):
            expected = round(math.pow(numeric_value, 1.0 / 3.0), 4)
            assert abs(actual[record["id"]] - expected) < 1e-4, (
                f"Incorrect cube root for {record['id']}: expected {expected}, "
                f"got {actual[record['id']]}"
            )
    finally:
        with open(DATA_FILE, "wb") as f:
            f.write(original_data)

    # Re-run against the project dataset so the required final output is generated
    # by the repaired script and can be checked by the original assertions below.
    run_process()


def test_results_file_exists():
    """Check if the results file was generated."""
    assert os.path.isfile(RESULTS_FILE), f"Expected output file {RESULTS_FILE} does not exist. Did you run the script?"


def test_results_content():
    """Check if the results file contains the correct calculated cube roots."""
    assert os.path.isfile(RESULTS_FILE), f"Expected output file {RESULTS_FILE} does not exist."

    expected_results = {
        "A1": 2.0,
        "B2": 3.0,
        "C3": 5.0,
        "D4": 4.0
    }

    actual_results = {}
    with open(RESULTS_FILE, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {RESULTS_FILE} is not valid JSON: {line}")

            assert "id" in data, f"Missing 'id' key in line {line_num}: {line}"
            assert "cube_root" in data, f"Missing 'cube_root' key in line {line_num}: {line}"

            actual_results[data["id"]] = data["cube_root"]

    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} records, but found {len(actual_results)}."

    for req_id, expected_val in expected_results.items():
        assert req_id in actual_results, f"Missing result for id '{req_id}'"
        actual_val = actual_results[req_id]
        assert isinstance(actual_val, (int, float)), f"Value for '{req_id}' is not a number: {actual_val}"
        assert abs(actual_val - expected_val) < 1e-4, f"Incorrect cube root for '{req_id}'. Expected {expected_val}, got {actual_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
