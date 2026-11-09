#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/process_hierarchy.py"
CSV_PATH = "/home/user/employees.csv"
JSON_PATH = "/home/user/hierarchy.json"


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_output():
    assert os.path.isfile(JSON_PATH), f"The file {JSON_PATH} was not created."
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")


def build_expected(records):
    employees = {
        row["emp_id"]: {
            "emp_id": row["emp_id"],
            "name": row["name"],
            "subordinates": [],
        }
        for row in records
    }
    roots = []
    for row in records:
        if row["manager_id"]:
            employees[row["manager_id"]]["subordinates"].append(employees[row["emp_id"]])
        else:
            roots.append(employees[row["emp_id"]])

    def sort_children(employee):
        employee["subordinates"].sort(key=lambda item: item["emp_id"])
        for child in employee["subordinates"]:
            sort_children(child)

    for root in roots:
        sort_children(root)
    return roots


def test_hierarchy_json_exists_and_content():
    assert os.path.isfile(SCRIPT_PATH), f"The file {SCRIPT_PATH} was not created."

    expected_structure = [
        {
            "emp_id": "1",
            "name": "Alice",
            "subordinates": [
                {
                    "emp_id": "2",
                    "name": "Bob",
                    "subordinates": [
                        {
                            "emp_id": "4",
                            "name": "David",
                            "subordinates": [
                                {
                                    "emp_id": "7",
                                    "name": "Grace",
                                    "subordinates": []
                                }
                            ]
                        },
                        {
                            "emp_id": "5",
                            "name": "Eve",
                            "subordinates": []
                        }
                    ]
                },
                {
                    "emp_id": "3",
                    "name": "Charlie",
                    "subordinates": [
                        {
                            "emp_id": "6",
                            "name": "Frank",
                            "subordinates": []
                        }
                    ]
                }
            ]
        },
        {
            "emp_id": "8",
            "name": "Heidi",
            "subordinates": [
                {
                    "emp_id": "9",
                    "name": "Ivan",
                    "subordinates": []
                }
            ]
        }
    ]

    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    run_script()
    actual_structure = load_output()
    assert actual_structure == expected_structure, f"The content of {JSON_PATH} does not match the expected hierarchical structure."


def test_script_processes_changed_csv():
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    with open(JSON_PATH, "rb") as f:
        original_json = f.read()

    ids = [str(value) for value in sorted(secrets.SystemRandom().sample(range(100000, 999999), 7))]
    names = [f"employee_{secrets.token_hex(8)}" for _ in ids]
    records = [
        {"emp_id": ids[0], "name": names[0], "manager_id": ""},
        {"emp_id": ids[4], "name": names[4], "manager_id": ""},
        {"emp_id": ids[5], "name": names[5], "manager_id": ids[0]},
        {"emp_id": ids[3], "name": names[3], "manager_id": ids[2]},
        {"emp_id": ids[2], "name": names[2], "manager_id": ids[0]},
        {"emp_id": ids[1], "name": names[1], "manager_id": ids[0]},
        {"emp_id": ids[6], "name": names[6], "manager_id": ids[4]},
    ]
    expected = build_expected(records)

    try:
        with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["emp_id", "name", "manager_id"])
            writer.writeheader()
            writer.writerows(records)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)

        run_script()
        actual = load_output()
        assert actual == expected, "The script did not correctly process a changed employees.csv file."
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        with open(JSON_PATH, "wb") as f:
            f.write(original_json)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
