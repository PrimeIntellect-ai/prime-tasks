#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import hashlib
import secrets
import subprocess
import pytest

INPUT_PATH = "/home/user/input_events.json"
CSV_PATH = "/home/user/masked.csv"
JSONL_PATH = "/home/user/final_features.jsonl"


def get_input_data():
    assert os.path.exists(INPUT_PATH), f"Input file {INPUT_PATH} is missing."
    with open(INPUT_PATH, "r") as f:
        return json.load(f)


def expected_for(data):
    csv_rows = []
    jsonl_rows = []
    for row in data:
        email_hash = hashlib.sha256(row["email"].encode("utf-8")).hexdigest()
        csv_rows.append({
            "id": str(row["id"]),
            "email_hash": email_hash,
            "event_type": row["event_type"],
            "value": str(row["value"]),
        })
        jsonl_rows.append({
            "id": row["id"],
            "email_hash": email_hash,
            "event_type": row["event_type"],
            "value_category": "HIGH" if row["value"] > 50 else "LOW",
        })
    return csv_rows, jsonl_rows


def assert_csv(data):
    assert os.path.exists(CSV_PATH), f"Intermediate CSV file {CSV_PATH} is missing."
    expected_rows, _ = expected_for(data)
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None, "CSV file has no header."
        expected_headers = ["id", "email_hash", "event_type", "value"]
        assert reader.fieldnames == expected_headers, (
            f"CSV headers {reader.fieldnames} do not match expected {expected_headers}."
        )
        actual_rows = list(reader)
    assert len(actual_rows) == len(expected_rows), "Incorrect number of rows in CSV."
    for actual, expected in zip(actual_rows, expected_rows):
        assert actual == expected, f"CSV row mismatch: expected {expected}, got {actual}."


def assert_jsonl(data):
    assert os.path.exists(JSONL_PATH), f"Final output file {JSONL_PATH} is missing."
    _, expected_lines = expected_for(data)
    with open(JSONL_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in JSONL, got {len(lines)}."
    )
    for i, (line, expected) in enumerate(zip(lines, expected_lines)):
        try:
            actual = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i + 1} in {JSONL_PATH} is not valid JSON.")
        assert actual == expected, (
            f"JSON object mismatch on line {i + 1}: expected {expected}, got {actual}."
        )


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_pipeline():
    token = secrets.token_hex(12)
    base_id = secrets.randbelow(500000) + 1000
    data = [
        {"id": base_id, "email": f"alpha-{token}@example.com", "ip_address": "203.0.113.11", "event_type": "view", "value": 0},
        {"id": base_id + 1, "email": f"beta-{token}@example.org", "ip_address": "198.51.100.22", "event_type": "buy", "value": 50},
        {"id": base_id + 2, "email": f"gamma-{token}@test.net", "ip_address": "192.0.2.33", "event_type": "click", "value": 51},
        {"id": base_id + 3, "email": f"delta-{token}@domain.org", "ip_address": "203.0.113.44", "event_type": "share", "value": 97},
    ]
    with open(INPUT_PATH, "w") as f:
        json.dump(data, f)

    for path in (CSV_PATH, JSONL_PATH):
        if os.path.lexists(path):
            os.remove(path)

    subprocess.run(
        ["python3", "/home/user/mask.py"],
        cwd="/home/user",
        check=True,
        timeout=20,
    )
    assert get_input_data() == data, "mask.py modified the input data."
    assert_csv(data)

    if os.path.lexists(JSONL_PATH):
        os.remove(JSONL_PATH)
    subprocess.run(
        ["node", "/home/user/extract.js"],
        cwd="/home/user",
        check=True,
        timeout=20,
    )
    assert get_input_data() == data, "extract.js modified the input data."
    assert_jsonl(data)

    for path in (CSV_PATH, JSONL_PATH):
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run(
        ["/home/user/run.sh"],
        cwd="/home/user",
        check=True,
        timeout=30,
    )
    assert get_input_data() == data, "run.sh modified the input data."
    assert_csv(data)
    assert_jsonl(data)


def test_scripts_exist_and_executable():
    """Test that the required scripts exist and run.sh is executable."""
    assert os.path.exists("/home/user/mask.py"), "/home/user/mask.py is missing."
    assert os.path.isfile("/home/user/mask.py"), "/home/user/mask.py is not a file."
    assert os.path.exists("/home/user/extract.js"), "/home/user/extract.js is missing."
    assert os.path.isfile("/home/user/extract.js"), "/home/user/extract.js is not a file."

    run_sh_path = "/home/user/run.sh"
    assert os.path.exists(run_sh_path), f"{run_sh_path} is missing."
    assert os.path.isfile(run_sh_path), f"{run_sh_path} is not a file."
    assert os.access(run_sh_path, os.X_OK), f"{run_sh_path} is not executable."


def test_masked_csv_output():
    """Test the intermediate output of Stage 1 (mask.py)."""
    csv_path = "/home/user/masked.csv"
    assert os.path.exists(csv_path), f"Intermediate CSV file {csv_path} is missing."

    input_data = get_input_data()
    expected_rows = []
    for row in input_data:
        email_hash = hashlib.sha256(row["email"].encode("utf-8")).hexdigest()
        expected_rows.append({
            "id": str(row["id"]),
            "email_hash": email_hash,
            "event_type": row["event_type"],
            "value": str(row["value"]),
        })

    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None, "CSV file has no header."
        expected_headers = ["id", "email_hash", "event_type", "value"]
        assert reader.fieldnames == expected_headers, f"CSV headers {reader.fieldnames} do not match expected {expected_headers}."
        actual_rows = list(reader)
        assert len(actual_rows) == len(expected_rows), "Incorrect number of rows in CSV."
        for actual, expected in zip(actual_rows, expected_rows):
            assert actual == expected, f"CSV row mismatch: expected {expected}, got {actual}."


def test_final_features_jsonl():
    """Test the final output of Stage 2 (extract.js)."""
    jsonl_path = "/home/user/final_features.jsonl"
    assert os.path.exists(jsonl_path), f"Final output file {jsonl_path} is missing."

    input_data = get_input_data()
    expected_lines = []
    for row in input_data:
        email_hash = hashlib.sha256(row["email"].encode("utf-8")).hexdigest()
        value_category = "HIGH" if row["value"] > 50 else "LOW"
        expected_lines.append({
            "id": row["id"],
            "email_hash": email_hash,
            "event_type": row["event_type"],
            "value_category": value_category,
        })

    with open(jsonl_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in JSONL, got {len(lines)}."
    for i, (line, expected) in enumerate(zip(lines, expected_lines)):
        try:
            actual = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i + 1} in {jsonl_path} is not valid JSON.")
        assert actual == expected, f"JSON object mismatch on line {i + 1}: expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
