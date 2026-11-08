#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from collections import defaultdict

import pytest

JSON_PATH = "/home/user/employees.json"
OUTPUT_PATH = "/home/user/bottleneck_chain.txt"

ORIGINAL_EMPLOYEES = [
    {"emp_id": 1, "name": "Alice", "manager_id": None},
    {"emp_id": 2, "name": "Bob", "manager_id": 1},
    {"emp_id": 3, "name": "Charlie", "manager_id": 1},
    {"emp_id": 4, "name": "David", "manager_id": 2},
    {"emp_id": 5, "name": "Eve", "manager_id": 2},
    {"emp_id": 6, "name": "Frank", "manager_id": 4},
    {"emp_id": 7, "name": "Grace", "manager_id": 4},
    {"emp_id": 8, "name": "Heidi", "manager_id": 4},
    {"emp_id": 9, "name": "Ivan", "manager_id": 4},
    {"emp_id": 10, "name": "Judy", "manager_id": 3},
    {"emp_id": 11, "name": "Mallory", "manager_id": 3},
    {"emp_id": 12, "name": "Niaj", "manager_id": 3},
]


def write_original_fixture():
    with open(JSON_PATH, "w") as f:
        json.dump(ORIGINAL_EMPLOYEES, f, indent=2)
        f.write("\n")


def load_json(path):
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {path} does not contain valid JSON.")


def find_script_candidates():
    candidates = []
    excluded_dirs = {"node_modules", "__pycache__", ".git", ".cache"}

    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in excluded_dirs and not d.startswith(".")]
        for name in files:
            if name.startswith("."):
                continue
            path = os.path.join(root, name)
            if path in {JSON_PATH, OUTPUT_PATH} or os.path.islink(path):
                continue
            if os.path.isfile(path):
                candidates.append(path)

    return sorted(candidates)


def commands_for_script(path):
    lower = path.lower()
    if lower.endswith(".py"):
        return [["python3", path]]
    if lower.endswith((".js", ".mjs", ".cjs")):
        return [["node", path]]
    if lower.endswith((".sh", ".bash")):
        return [["bash", path]]

    try:
        with open(path, "rb") as f:
            first_line = f.readline(256).decode("utf-8", "ignore").lower()
    except OSError:
        first_line = ""

    if first_line.startswith("#!"):
        if "python" in first_line:
            return [["python3", path]]
        if "node" in first_line:
            return [["node", path]]
        if "bash" in first_line or first_line.rstrip().endswith("/sh"):
            return [["bash", path]]

    # The instruction does not prescribe a filename extension or executable bit.
    return [["python3", path], ["node", path], ["bash", path]]


def execute_submission_script():
    candidates = find_script_candidates()
    assert candidates, "No submission script was found under /home/user."

    failures = []
    for path in candidates:
        for command in commands_for_script(path):
            write_original_fixture()
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)

            try:
                result = subprocess.run(
                    command,
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                    check=False,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                failures.append(f"{command}: {exc}")
                continue

            if result.returncode != 0:
                failures.append(
                    f"{command}: exited {result.returncode}; stderr={result.stderr[-500:]}"
                )
                continue
            if not os.path.isfile(OUTPUT_PATH):
                failures.append(f"{command}: did not create {OUTPUT_PATH}")
                continue

            try:
                current_fixture = load_json(JSON_PATH)
            except (OSError, pytest.fail.Exception):
                failures.append(f"{command}: damaged the input fixture")
                continue

            if current_fixture != ORIGINAL_EMPLOYEES:
                failures.append(f"{command}: modified the input fixture")
                continue

            return path

    pytest.fail(
        "No submitted script executed successfully and generated the output.\n"
        + "\n".join(failures[-10:])
    )


def test_bottleneck_chain_output():
    assert os.path.isfile(JSON_PATH), f"Input file {JSON_PATH} is missing."
    employees_before = load_json(JSON_PATH)
    assert employees_before == ORIGINAL_EMPLOYEES, (
        f"Input file {JSON_PATH} was changed from the supplied employee fixture."
    )

    execute_submission_script()

    assert os.path.isfile(JSON_PATH), f"Input file {JSON_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."

    employees = load_json(JSON_PATH)
    assert employees == ORIGINAL_EMPLOYEES, (
        f"Input file {JSON_PATH} does not match the supplied employee fixture."
    )

    reports_count = defaultdict(int)
    emp_dict = {}
    ceo_id = None

    for emp in employees:
        emp_dict[emp["emp_id"]] = emp
        if emp["manager_id"] is None:
            ceo_id = emp["emp_id"]
        else:
            reports_count[emp["manager_id"]] += 1

    assert ceo_id is not None, "No CEO (manager_id = null) found in the dataset."
    assert reports_count, "No reports found in the dataset."

    bottleneck_id = None
    max_reports = -1
    for mgr_id, count in reports_count.items():
        if count > max_reports:
            max_reports = count
            bottleneck_id = mgr_id
        elif count == max_reports:
            if bottleneck_id is None or mgr_id < bottleneck_id:
                bottleneck_id = mgr_id

    assert bottleneck_id is not None, "Could not identify a bottleneck manager."

    path = []
    current_id = bottleneck_id
    visited = set()
    while current_id is not None:
        if current_id in visited:
            pytest.fail("Cycle detected in the management chain.")
        visited.add(current_id)

        emp = emp_dict.get(current_id)
        assert emp is not None, f"Employee ID {current_id} not found."
        path.append(emp["name"])

        if current_id == ceo_id:
            break
        current_id = emp["manager_id"]

    path.reverse()
    expected_output = " -> ".join(path)

    with open(OUTPUT_PATH, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        f"Output in {OUTPUT_PATH} is incorrect.\n"
        f"Expected: '{expected_output}'\n"
        f"Actual:   '{actual_output}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
