#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp -a /home/user/data/. "$backup_dir/"
restore_data() {
    rm -rf /home/user/data
    mkdir -p /home/user/data
    cp -a "$backup_dir/." /home/user/data/
    rm -rf "$backup_dir"
}
trap restore_data EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/analyze.sh"
RESULT_PATH = "/home/user/result.json"
EMP_PATH = "/home/user/data/emp.csv"
PROJ_PATH = "/home/user/data/proj.csv"


def run_script():
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        ["bash", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"analyze.sh exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def load_result():
    assert os.path.isfile(RESULT_PATH), f"The file {RESULT_PATH} is missing."
    try:
        with open(RESULT_PATH, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {RESULT_PATH} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {RESULT_PATH}: {e}")


def derive_expected():
    with open(EMP_PATH, newline="") as f:
        employees = list(csv.DictReader(f))

    by_id = {row["emp_id"]: row for row in employees}
    assert "E001" in by_id

    included = set()
    pending = ["E001"]
    while pending:
        emp_id = pending.pop()
        if emp_id in included:
            continue
        included.add(emp_id)
        pending.extend(
            row["emp_id"] for row in employees
            if row["manager_id"] == emp_id and row["emp_id"] not in included
        )

    total_salary = sum(int(by_id[emp_id]["salary"]) for emp_id in included)
    dept_by_emp = {row["emp_id"]: row["dept_id"] for row in employees}
    project_departments = {}
    with open(PROJ_PATH, newline="") as f:
        for row in csv.DictReader(f):
            project_departments.setdefault(row["proj_id"], set()).add(
                dept_by_emp[row["emp_id"]]
            )

    projects = sorted(
        project for project, departments in project_departments.items()
        if len(departments) >= 3
    )
    return {
        "total_salary_tree_E001": total_salary,
        "cross_dept_projects": projects,
    }


def write_case(case_number):
    token = secrets.token_hex(4).upper()
    departments = [f"D{token}{i}" for i in range(1, 7)]
    salaries = [secrets.randbelow(80000) + 1000 for _ in range(7)]

    if case_number == 0:
        employees = [
            ["E001", "Root", "", departments[0], salaries[0]],
            ["A101", "A", "E001", departments[1], salaries[1]],
            ["A102", "B", "A101", departments[2], salaries[2]],
            ["A103", "C", "A102", departments[0], salaries[3]],
            ["A104", "D", "E001", departments[3], salaries[4]],
            ["X201", "X", "", departments[4], salaries[5]],
            ["X202", "Y", "X201", departments[5], salaries[6]],
        ]
    else:
        employees = [
            ["E001", "Root", "", departments[0], salaries[0]],
            ["B101", "A", "E001", departments[1], salaries[1]],
            ["B102", "B", "E001", departments[2], salaries[2]],
            ["B103", "C", "B101", departments[3], salaries[3]],
            ["B104", "D", "B103", departments[4], salaries[4]],
            ["Z201", "X", "", departments[5], salaries[5]],
            ["Z202", "Y", "Z201", departments[0], salaries[6]],
        ]

    project_ids = [f"P{secrets.token_hex(5).upper()}" for _ in range(4)]
    if case_number == 0:
        assignments = [
            ["E001", project_ids[0]], ["A101", project_ids[0]], ["A102", project_ids[0]],
            ["E001", project_ids[1]], ["A103", project_ids[1]], ["A101", project_ids[1]],
            ["A104", project_ids[2]], ["X201", project_ids[2]], ["X202", project_ids[2]],
            ["A101", project_ids[3]], ["A102", project_ids[3]], ["A104", project_ids[3]],
        ]
    else:
        assignments = [
            ["E001", project_ids[0]], ["B101", project_ids[0]], ["B102", project_ids[0]],
            ["B101", project_ids[1]], ["B103", project_ids[1]],
            ["B102", project_ids[2]], ["B104", project_ids[2]], ["Z201", project_ids[2]],
            ["E001", project_ids[3]], ["Z202", project_ids[3]],
        ]

    with open(EMP_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["emp_id", "name", "manager_id", "dept_id", "salary"])
        writer.writerows(employees)

    with open(PROJ_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["emp_id", "proj_id"])
        writer.writerows(assignments)


def test_analyze_script_exists():
    script_path = '/home/user/analyze.sh'
    assert os.path.isfile(script_path), f"The script {script_path} is missing."


def test_analyze_script_runs_on_supplied_data():
    run_script()


def test_result_json_exists():
    result_path = '/home/user/result.json'
    assert os.path.isfile(result_path), f"The file {result_path} is missing."


def test_result_json_content():
    data = load_result()

    # Check total_salary_tree_E001
    assert "total_salary_tree_E001" in data, "The key 'total_salary_tree_E001' is missing from the JSON output."
    expected_salary = 40000
    actual_salary = data["total_salary_tree_E001"]
    assert actual_salary == expected_salary, f"Expected 'total_salary_tree_E001' to be {expected_salary}, but got {actual_salary}."

    # Check cross_dept_projects
    assert "cross_dept_projects" in data, "The key 'cross_dept_projects' is missing from the JSON output."
    expected_projects = ["P2", "P4"]
    actual_projects = data["cross_dept_projects"]
    assert isinstance(actual_projects, list), "The 'cross_dept_projects' value must be a JSON array."
    assert actual_projects == expected_projects, f"Expected 'cross_dept_projects' to be {expected_projects}, but got {actual_projects}."


def test_script_computes_results_for_unseen_data():
    baseline_result = None
    if os.path.isfile(RESULT_PATH):
        with open(RESULT_PATH, "rb") as f:
            baseline_result = f.read()

    try:
        for case_number in range(2):
            write_case(case_number)
            expected = derive_expected()
            run_script()
            actual = load_result()
            assert set(actual.keys()) == {
                "total_salary_tree_E001", "cross_dept_projects"
            }, "result.json must contain exactly the two required keys."
            assert type(actual["total_salary_tree_E001"]) is int, (
                "The total salary must be a JSON integer."
            )
            assert actual["cross_dept_projects"] == sorted(actual["cross_dept_projects"]), (
                "The project array must be sorted alphabetically."
            )
            assert actual == expected, (
                f"Incorrect output for dynamically generated input. "
                f"Expected {expected}, got {actual}."
            )
    finally:
        if baseline_result is not None:
            with open(RESULT_PATH, "wb") as f:
                f.write(baseline_result)
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
