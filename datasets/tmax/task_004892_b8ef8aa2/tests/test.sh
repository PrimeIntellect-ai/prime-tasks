#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import uuid

import pytest

ETL_PATH = "/home/user/etl.go"
RAW_PATH = "/home/user/raw_data.jsonl"
SUMMARY_PATH = "/home/user/summary.json"


def run_etl(status):
    return subprocess.run(
        ["go", "run", ETL_PATH, status],
        capture_output=True,
        text=True,
        timeout=60,
    )


def load_summary():
    assert os.path.exists(SUMMARY_PATH), f"{SUMMARY_PATH} was not created after running the program."
    with open(SUMMARY_PATH, "r") as f:
        return json.load(f)


def assert_strict_summary(data, expected):
    assert isinstance(data, list), "Output must be a JSON array."
    assert len(data) == len(expected), f"Expected {len(expected)} records, found {len(data)}."

    user_ids = []
    for i, record in enumerate(data):
        assert isinstance(record, dict), f"Record {i} must be an object."
        assert set(record.keys()) == {"user_id", "total_spend"}, \
            f"Record {i} must contain exactly user_id and total_spend."
        assert isinstance(record["user_id"], str) and record["user_id"] != "", \
            f"Record {i} has an invalid user_id."
        assert isinstance(record["total_spend"], (int, float)) and not isinstance(record["total_spend"], bool), \
            f"Record {i} has a non-numeric total_spend."
        assert record["total_spend"] > 0, f"Record {i} has a non-positive total_spend."
        user_ids.append(record["user_id"])

    assert user_ids == sorted(user_ids), "Records must be ordered alphabetically by user_id."

    for i, exp in enumerate(expected):
        assert data[i]["user_id"] == exp["user_id"], \
            f"Expected user_id {exp['user_id']} at index {i}, got {data[i]['user_id']}"
        assert float(data[i]["total_spend"]) == pytest.approx(exp["total_spend"]), \
            f"Incorrect total_spend for {exp['user_id']}"


def test_etl_go_exists():
    """Test that the Go program exists."""
    assert os.path.exists(ETL_PATH), f"{ETL_PATH} does not exist."
    assert os.path.isfile(ETL_PATH), f"{ETL_PATH} is not a regular file."


def test_summary_json_exists_and_correct():
    """Test that summary.json exists and contains the correct aggregated data for 'completed'."""
    assert os.path.exists(SUMMARY_PATH), f"{SUMMARY_PATH} does not exist."

    with open(SUMMARY_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{SUMMARY_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "Output must be a JSON array."

    expected = [
        {"user_id": "u001", "total_spend": 40.0},
        {"user_id": "u003", "total_spend": 45.5}
    ]

    assert len(data) == len(expected), f"Expected {len(expected)} records, found {len(data)}."

    for i, exp in enumerate(expected):
        record = data[i]
        assert "user_id" in record, f"Record {i} missing 'user_id'"
        assert "total_spend" in record, f"Record {i} missing 'total_spend'"
        assert record["user_id"] == exp["user_id"], f"Expected user_id {exp['user_id']} at index {i}, got {record['user_id']}"
        assert float(record["total_spend"]) == exp["total_spend"], f"Expected total_spend {exp['total_spend']} at index {i}, got {record['total_spend']}"


def test_etl_go_execution():
    """Test that the Go program can be executed with a different argument and produces correct results."""
    result = run_etl("pending")
    assert result.returncode == 0, f"Go program failed to execute: {result.stderr}"

    data = load_summary()
    expected = [{"user_id": "u002", "total_spend": 100.0}]

    assert len(data) == len(expected), f"Expected {len(expected)} records for 'pending', found {len(data)}."
    assert data[0]["user_id"] == "u002", "Expected user_id 'u002' for 'pending' status."
    assert float(data[0]["total_spend"]) == 100.0, "Expected total_spend 100.0 for 'u002'."


def test_dynamic_input_filtering_aggregation_and_schema():
    """Exercise the program against unpredictable data and status arguments."""
    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()
    original_summary = None
    if os.path.exists(SUMMARY_PATH):
        with open(SUMMARY_PATH, "rb") as f:
            original_summary = f.read()

    token = uuid.uuid4().hex
    status_one = "dynamic status " + token[:10]
    status_two = "other-" + token[10:20]
    unrelated_status = "ignored-" + token[20:]

    user_a = "z-user-" + token[:8]
    user_b = "a-user-" + token[8:16]
    user_nonpositive = "m-user-" + token[16:24]
    user_zero = "q-user-" + token[24:32]
    user_other = "b-user-" + token[:8]

    base = random.SystemRandom().randint(11, 90)
    second = random.SystemRandom().randint(3, 20)

    documents = [
        {"user_id": user_a, "status": status_one,
         "items": [{"price": base + 0.25, "quantity": 2}, {"price": 1.5, "quantity": 3}]},
        {"user_id": user_a, "status": status_one, "total_amount": second + 0.25},
        {"user_id": user_b, "status": status_one, "total_amount": base + 7.5},
        {"user_id": user_b, "status": status_one,
         "items": [{"price": 2.25, "quantity": 4}]},
        {"user_id": user_nonpositive, "status": status_one, "total_amount": -50.0},
        {"user_id": user_nonpositive, "status": status_one,
         "items": [{"price": 10.0, "quantity": 2}]},
        {"user_id": user_zero, "status": status_one,
         "items": [{"price": 0.0, "quantity": 9}]},
        {"user_id": "", "status": status_one, "total_amount": 99.0},
        {"user_id": user_other, "status": status_two,
         "items": [{"price": second + 0.5, "quantity": 3}]},
        {"user_id": user_a, "status": unrelated_status, "total_amount": 99999.0},
    ]
    random.SystemRandom().shuffle(documents)

    expected_one = sorted([
        {"user_id": user_a, "total_spend": (base + 0.25) * 2 + 1.5 * 3 + second + 0.25},
        {"user_id": user_b, "total_spend": base + 7.5 + 2.25 * 4},
    ], key=lambda row: row["user_id"])
    expected_two = [
        {"user_id": user_other, "total_spend": (second + 0.5) * 3}
    ]

    try:
        with open(RAW_PATH, "w") as f:
            for document in documents:
                f.write(json.dumps(document) + "\n")

        for status, expected in ((status_one, expected_one), (status_two, expected_two)):
            with open(SUMMARY_PATH, "w") as f:
                f.write('{"stale":true}')
            result = run_etl(status)
            assert result.returncode == 0, \
                f"Go program failed for status {status!r}: {result.stderr}"
            assert_strict_summary(load_summary(), expected)

        no_arg = subprocess.run(
            ["go", "run", ETL_PATH], capture_output=True, text=True, timeout=60
        )
        assert no_arg.returncode != 0, "Program must reject a missing status argument."

        extra_arg = subprocess.run(
            ["go", "run", ETL_PATH, status_one, "extra"],
            capture_output=True, text=True, timeout=60
        )
        assert extra_arg.returncode != 0, "Program must reject more than one argument."
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        if original_summary is None:
            if os.path.exists(SUMMARY_PATH):
                os.remove(SUMMARY_PATH)
        else:
            with open(SUMMARY_PATH, "wb") as f:
                f.write(original_summary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
