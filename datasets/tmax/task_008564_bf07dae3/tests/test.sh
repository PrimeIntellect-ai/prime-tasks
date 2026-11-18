#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import random
import subprocess
from datetime import datetime, timedelta, timezone
import pytest

BINARY = "/tmp/pipeline_under_test"
VALID_RELS_PATH = "/home/user/data/valid_relationships.csv"
CORRUPTED_PATH = "/home/user/data/corrupted_export.csv"
OUTPUT_PATH = "/home/user/page3.json"


def compute_expected(valid_rels_path, corrupted_path):
    valid_rels = set()
    with open(valid_rels_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            valid_rels.add((row["UserID"], row["DepartmentID"]))

    valid_events = []
    with open(corrupted_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if (row["UserID"], row["DepartmentID"]) in valid_rels:
                valid_events.append({
                    "event_id": row["EventID"],
                    "user_id": row["UserID"],
                    "department_id": row["DepartmentID"],
                    "timestamp": row["Timestamp"],
                    "action": row["Action"],
                })

    valid_events.sort(key=lambda x: x["event_id"])
    valid_events.sort(key=lambda x: x["timestamp"], reverse=True)
    return valid_events[30:45]


def load_output():
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} does not exist. Did you run your Go program?"
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT_PATH} does not contain valid JSON.")


def assert_output_matches(actual_page3, expected_page3):
    assert isinstance(actual_page3, list), f"Expected the output in {OUTPUT_PATH} to be a JSON array."
    assert len(actual_page3) == len(expected_page3), f"Expected {len(expected_page3)} items in Page 3, but found {len(actual_page3)}."

    for i, (actual, expected) in enumerate(zip(actual_page3, expected_page3)):
        assert actual.get("event_id") == expected["event_id"], f"Item at index {i} has incorrect event_id. Expected {expected['event_id']}, got {actual.get('event_id')}."
        assert actual.get("user_id") == expected["user_id"], f"Item at index {i} has incorrect user_id. Expected {expected['user_id']}, got {actual.get('user_id')}."
        assert actual.get("department_id") == expected["department_id"], f"Item at index {i} has incorrect department_id. Expected {expected['department_id']}, got {actual.get('department_id')}."
        assert actual.get("timestamp") == expected["timestamp"], f"Item at index {i} has incorrect timestamp. Expected {expected['timestamp']}, got {actual.get('timestamp')}."
        assert actual.get("action") == expected["action"], f"Item at index {i} has incorrect action. Expected {expected['action']}, got {actual.get('action')}."


def test_pipeline_go_exists():
    assert os.path.isfile("/home/user/pipeline.go"), "/home/user/pipeline.go does not exist. You must write your Go program here."


def test_page3_json_matches_expected():
    expected_page3 = compute_expected(VALID_RELS_PATH, CORRUPTED_PATH)
    actual_page3 = load_output()
    assert_output_matches(actual_page3, expected_page3)


def test_compiled_pipeline_on_alternate_inputs():
    paths = [VALID_RELS_PATH, CORRUPTED_PATH, OUTPUT_PATH]
    backups = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                backups[path] = f.read()
        else:
            backups[path] = None

    relationships = [
        ("QA", "DX"),
        ("QB", "DY"),
        ("QC", "DZ"),
        ("QD", "DW"),
        ("QE", "DV"),
    ]
    actions = ["LOGIN", "VIEW", "CLICK", "LOGOUT"]
    base = datetime(2025, 2, 3, 8, 0, tzinfo=timezone.utc)
    rows = []

    for i in range(68):
        user, department = relationships[i % len(relationships)]
        timestamp = (base + timedelta(minutes=(i * 7) % 19)).strftime("%Y-%m-%dT%H:%M:%SZ")
        rows.append({
            "EventID": f"T{(i * 29) % 211:03d}",
            "UserID": user,
            "DepartmentID": department,
            "Timestamp": timestamp,
            "Action": actions[i % len(actions)],
        })

        invalid_department = relationships[(i + 1) % len(relationships)][1]
        rows.append({
            "EventID": f"BAD{i:03d}",
            "UserID": user,
            "DepartmentID": invalid_department,
            "Timestamp": (base + timedelta(minutes=100 + i)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "Action": "INVALID",
        })

    random.Random(917).shuffle(rows)

    try:
        with open(VALID_RELS_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["UserID", "DepartmentID"])
            writer.writerows(relationships)

        with open(CORRUPTED_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(
                f,
                fieldnames=["EventID", "UserID", "DepartmentID", "Timestamp", "Action"],
                lineterminator="\n",
            )
            writer.writeheader()
            writer.writerows(rows)

        expected_page3 = compute_expected(VALID_RELS_PATH, CORRUPTED_PATH)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        subprocess.run([BINARY], cwd="/home/user", check=True, timeout=30)
        actual_page3 = load_output()
        assert_output_matches(actual_page3, expected_page3)
    finally:
        for path, contents in backups.items():
            if contents is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(contents)
TEST_EOF

if go build -o /tmp/pipeline_under_test /home/user/pipeline.go \
   && rm -f /home/user/page3.json \
   && timeout 30s /tmp/pipeline_under_test \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
