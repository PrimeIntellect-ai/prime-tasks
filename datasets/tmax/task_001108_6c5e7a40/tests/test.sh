#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import csv
import os
import random
import subprocess
import pytest

SCRIPT_PATH = "/home/user/org_rollup.py"
EMPLOYEES_PATH = "/home/user/employees.csv"
DEPARTMENTS_PATH = "/home/user/departments.csv"


def run_script(manager_id):
    return subprocess.run(
        ["python3", SCRIPT_PATH, str(manager_id)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_script_requirements():
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    content_upper = content.upper()
    assert "WITH RECURSIVE" in content_upper, "Script does not use 'WITH RECURSIVE' CTE as required."
    assert "SQLITE3" in content_upper, "Script does not use sqlite3 module."
    assert "CSV" in content_upper, "Script does not use csv module."
    assert "PANDAS" not in content_upper, "Script should not use external libraries like pandas."


@pytest.mark.parametrize("manager_id, expected_output", [
    ("2", "353000.00"),
    ("5", "144000.00"),
    ("1", "538000.00"),
    ("3", "85000.00"),
    ("4", "121000.00"),
    ("6", "55000.00"),
    ("7", "66000.00"),
])
def test_script_output(manager_id, expected_output):
    result = run_script(manager_id)
    assert result.returncode == 0, f"Script failed for manager_id {manager_id} with error: {result.stderr}"

    output = result.stdout.strip()
    assert output == expected_output, f"Expected output {expected_output} for manager_id {manager_id}, but got {output}"


def expected_rollup(manager_id, employees, modifiers):
    subtree = {manager_id}
    changed = True
    while changed:
        changed = False
        for employee in employees:
            if employee["manager_id"] in subtree and employee["id"] not in subtree:
                subtree.add(employee["id"])
                changed = True

    total = sum(
        employee["salary"] * modifiers[employee["dept_id"]]
        for employee in employees
        if employee["id"] in subtree
    )
    return f"{total:.2f}"


def test_generated_organization_and_changed_csv_data():
    rng = random.Random(847291)
    employee_ids = rng.sample(range(101, 900), 19)
    dept_ids = rng.sample(range(20, 90), 4)
    modifiers = {
        dept_ids[0]: 0.75,
        dept_ids[1]: 1.00,
        dept_ids[2]: 1.25,
        dept_ids[3]: 1.50,
    }

    employees = []
    for index, employee_id in enumerate(employee_ids):
        manager_id = None if index == 0 else rng.choice(employee_ids[:index])
        employees.append({
            "id": employee_id,
            "name": f"Generated Employee {index}",
            "manager_id": manager_id,
            "salary": rng.randrange(160, 960) * 100,
            "dept_id": rng.choice(dept_ids),
        })

    original_employees = open(EMPLOYEES_PATH, "rb").read()
    original_departments = open(DEPARTMENTS_PATH, "rb").read()

    try:
        with open(EMPLOYEES_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "name", "manager_id", "salary", "dept_id"])
            shuffled = employees[:]
            rng.shuffle(shuffled)
            for employee in shuffled:
                writer.writerow([
                    employee["id"],
                    employee["name"],
                    "" if employee["manager_id"] is None else employee["manager_id"],
                    employee["salary"],
                    employee["dept_id"],
                ])

        with open(DEPARTMENTS_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["dept_id", "dept_name", "budget_modifier"])
            for index, dept_id in enumerate(reversed(dept_ids)):
                writer.writerow([dept_id, f"Generated Department {index}", modifiers[dept_id]])

        order = employee_ids[:]
        rng.shuffle(order)
        for manager_id in order:
            expected = expected_rollup(manager_id, employees, modifiers)
            result = run_script(manager_id)
            assert result.returncode == 0, (
                f"Script failed for generated manager_id {manager_id}: {result.stderr}"
            )
            assert result.stdout.strip() == expected, (
                f"Expected output {expected} for generated manager_id {manager_id}, "
                f"but got {result.stdout.strip()}"
            )
    finally:
        with open(EMPLOYEES_PATH, "wb") as f:
            f.write(original_employees)
        with open(DEPARTMENTS_PATH, "wb") as f:
            f.write(original_departments)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
