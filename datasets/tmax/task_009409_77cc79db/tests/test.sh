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

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "process_data.py")
OUTPUT = os.path.join(HOME, "top_communicators.json")
EMPLOYEES = os.path.join(HOME, "employees.csv")
INTERACTIONS = os.path.join(HOME, "interactions.csv")


def run_script():
    subprocess.run(
        ["python3", SCRIPT],
        cwd=HOME,
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_process_data_script_exists():
    assert os.path.isfile(SCRIPT), f"Expected Python script {SCRIPT} is missing."


def test_top_communicators_json_exists():
    file_path = "/home/user/top_communicators.json"
    assert os.path.isfile(file_path), f"Expected output file {file_path} is missing."


def test_top_communicators_json_content():
    run_script()

    file_path = "/home/user/top_communicators.json"
    assert os.path.isfile(file_path), f"Expected output file {file_path} is missing."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    expected_data = [
        {
            "department": "Engineering",
            "emp_id": 3,
            "name": "Charlie",
            "interaction_count": 4
        },
        {
            "department": "Engineering",
            "emp_id": 4,
            "name": "David",
            "interaction_count": 2
        },
        {
            "department": "HR",
            "emp_id": 6,
            "name": "Frank",
            "interaction_count": 2
        },
        {
            "department": "HR",
            "emp_id": 7,
            "name": "Grace",
            "interaction_count": 0
        },
        {
            "department": "Sales",
            "emp_id": 1,
            "name": "Alice",
            "interaction_count": 4
        },
        {
            "department": "Sales",
            "emp_id": 2,
            "name": "Bob",
            "interaction_count": 2
        }
    ]

    assert isinstance(data, list), "Output JSON must be a list of objects."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, but got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert actual == expected, f"Item at index {i} does not match expected output.\nExpected: {expected}\nActual: {actual}"


def test_script_processes_changed_inputs_and_generalizes():
    original_employees = open(EMPLOYEES, "rb").read()
    original_interactions = open(INTERACTIONS, "rb").read()
    original_output = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None

    ids = sorted(secrets.SystemRandom().sample(range(1000, 9000), 6))
    employee_rows = [
        {"emp_id": ids[4], "name": "Aster", "department": "Gamma"},
        {"emp_id": ids[0], "name": "Birch", "department": "Alpha"},
        {"emp_id": ids[5], "name": "Cedar", "department": "Alpha"},
        {"emp_id": ids[2], "name": "Dahlia", "department": "Gamma"},
        {"emp_id": ids[1], "name": "Elm", "department": "Alpha"},
        {"emp_id": ids[3], "name": "Fir", "department": "Solo"},
    ]

    a0, a1, a2 = ids[0], ids[1], ids[5]
    g0, g1 = ids[2], ids[4]
    solo = ids[3]
    invalid = 99000 + secrets.randbelow(900)
    interaction_pairs = [
        (a0, a1), (a0, a1),
        (a0, a2),
        (a1, g0),
        (g0, g1), (g0, g1), (g0, g1),
        (a2, a2),
        (invalid, a0),
        (g1, invalid),
    ]

    counts = {row["emp_id"]: 0 for row in employee_rows}
    valid_ids = set(counts)
    for source, target in interaction_pairs:
        if source in valid_ids and target in valid_ids:
            counts[source] += 1
            counts[target] += 1

    expected = []
    departments = sorted({row["department"] for row in employee_rows})
    for department in departments:
        members = [row for row in employee_rows if row["department"] == department]
        members.sort(key=lambda row: (-counts[row["emp_id"]], row["emp_id"]))
        for row in members[:2]:
            expected.append({
                "department": row["department"],
                "emp_id": row["emp_id"],
                "name": row["name"],
                "interaction_count": counts[row["emp_id"]],
            })

    try:
        with open(EMPLOYEES, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["emp_id", "name", "department"])
            writer.writeheader()
            writer.writerows(employee_rows)

        with open(INTERACTIONS, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["source_id", "target_id", "timestamp", "interaction_type"])
            for i, (source, target) in enumerate(interaction_pairs):
                writer.writerow([source, target, f"2026-01-01T00:{i:02d}:00", "test"])

        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        run_script()
        assert os.path.isfile(OUTPUT), "The script did not create top_communicators.json."

        with open(OUTPUT, "r") as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("Output for changed inputs is not valid JSON.")

        assert isinstance(actual, list), "Output JSON must be a list of objects."
        for i, item in enumerate(actual):
            assert isinstance(item, dict), f"Item at index {i} is not a JSON object."
            assert set(item) == {"department", "emp_id", "name", "interaction_count"}, \
                f"Item at index {i} does not have exactly the required schema."
        assert actual == expected, f"Script did not correctly process changed CSV inputs.\nExpected: {expected}\nActual: {actual}"
    finally:
        with open(EMPLOYEES, "wb") as f:
            f.write(original_employees)
        with open(INTERACTIONS, "wb") as f:
            f.write(original_interactions)
        if original_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
