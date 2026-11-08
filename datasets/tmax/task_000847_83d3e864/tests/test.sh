#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/etl.sh"
EMPLOYEES_PATH = "/home/user/employees.csv"
REPORTING_PATH = "/home/user/reporting.csv"
OUTPUT_PATH = "/home/user/manager_summary.csv"


def write_file(path, content):
    with open(path, "w", newline="") as f:
        f.write(content)


def run_etl():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        f"The output file {OUTPUT_PATH} does not exist after running the script."
    )


def test_etl_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_manager_summary_csv_content():
    write_file(
        EMPLOYEES_PATH,
        """id,name,department,salary
1,Alice,Exec,200000
2,Bob,Engineering,150000
3,Charlie,Engineering,120000
4,Diana,Engineering,110000
5,Eve,Sales,130000
6,Frank,Sales,90000
7,Grace,Engineering,100000
8,Heidi,Sales,80000
9,Ivan,Exec,150000
""",
    )
    write_file(
        REPORTING_PATH,
        """emp_id,manager_id
2,1
5,1
3,2
4,2
6,5
7,3
8,6
""",
    )

    run_etl()

    expected_content = """manager_id,manager_name,department,direct_reports_count,total_descendant_salary
1,Alice,Exec,2,780000
2,Bob,Engineering,2,330000
3,Charlie,Engineering,1,100000
5,Eve,Sales,1,170000
6,Frank,Sales,1,80000"""

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    assert content == expected_content, (
        f"The content of {OUTPUT_PATH} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )


def test_etl_computes_fresh_results_for_unseen_hierarchy():
    rng = secrets.SystemRandom()
    count = 13
    ids = rng.sample(range(20, 900), count)
    salaries = [rng.randrange(40000, 220001) for _ in range(count)]
    departments = ["DeptA", "DeptB", "DeptC", "DeptD"]

    employees = {}
    employee_rows = []
    for i, emp_id in enumerate(ids):
        name = f"Employee{i}"
        department = departments[rng.randrange(len(departments))]
        employees[emp_id] = (name, department, salaries[i])
        employee_rows.append((emp_id, name, department, salaries[i]))

    # Build a valid, randomly varying hierarchy. The first three links force
    # indirect descendants; remaining employees choose an earlier manager.
    edges = []
    for i in range(1, count):
        if i == 1:
            manager_index = 0
        elif i == 2:
            manager_index = 1
        elif i == 3:
            manager_index = 2
        else:
            manager_index = rng.randrange(i)
        edges.append((ids[i], ids[manager_index]))

    rng.shuffle(employee_rows)
    shuffled_edges = list(edges)
    rng.shuffle(shuffled_edges)

    employee_text = "id,name,department,salary\n" + "\n".join(
        f"{emp_id},{name},{department},{salary}"
        for emp_id, name, department, salary in employee_rows
    ) + "\n"
    reporting_text = "emp_id,manager_id\n" + "\n".join(
        f"{emp_id},{manager_id}" for emp_id, manager_id in shuffled_edges
    ) + "\n"
    write_file(EMPLOYEES_PATH, employee_text)
    write_file(REPORTING_PATH, reporting_text)

    children = {}
    for emp_id, manager_id in edges:
        children.setdefault(manager_id, []).append(emp_id)

    def descendant_salary(manager_id):
        total = 0
        stack = list(children.get(manager_id, []))
        while stack:
            emp_id = stack.pop()
            total += employees[emp_id][2]
            stack.extend(children.get(emp_id, []))
        return total

    expected_lines = [
        "manager_id,manager_name,department,direct_reports_count,total_descendant_salary"
    ]
    for manager_id in sorted(children):
        name, department, _ = employees[manager_id]
        expected_lines.append(
            f"{manager_id},{name},{department},{len(children[manager_id])},"
            f"{descendant_salary(manager_id)}"
        )
    expected_content = "\n".join(expected_lines)

    run_etl()

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    assert content == expected_content, (
        "The script did not compute the correct report for a fresh hierarchy.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
