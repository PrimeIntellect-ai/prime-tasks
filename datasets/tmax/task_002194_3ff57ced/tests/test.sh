#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import pwd
import random
import subprocess
from collections import defaultdict


def test_process_data_cpp_exists():
    file_path = "/home/user/process_data.cpp"
    assert os.path.isfile(file_path), f"File {file_path} is missing."


def test_summary_csv_correct():
    summary_path = "/home/user/summary.csv"
    assert os.path.isfile(summary_path), f"File {summary_path} is missing."

    employees_path = "/home/user/employees.csv"
    projects_path = "/home/user/projects.csv"

    assert os.path.isfile(employees_path), "Input employees.csv is missing."
    assert os.path.isfile(projects_path), "Input projects.csv is missing."

    employees = {}
    children = defaultdict(list)

    with open(employees_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            emp_id = int(row["emp_id"])
            manager_id = row["manager_id"].strip()
            employees[emp_id] = {"hours": 0, "cost": 0}
            if manager_id:
                children[int(manager_id)].append(emp_id)

    with open(projects_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            emp_id = int(row["emp_id"])
            if emp_id in employees:
                employees[emp_id]["hours"] += int(row["hours"])
                employees[emp_id]["cost"] += int(row["cost"])

    def rollup(emp_id):
        total_hours = employees[emp_id]["hours"]
        total_cost = employees[emp_id]["cost"]
        for child in children[emp_id]:
            child_hours, child_cost = rollup(child)
            total_hours += child_hours
            total_cost += child_cost
        return total_hours, total_cost

    expected_results = {}
    for emp_id in employees:
        expected_results[emp_id] = rollup(emp_id)

    expected_rows = ["emp_id,total_hours,total_cost"]
    for emp_id in sorted(expected_results.keys()):
        total_hours, total_cost = expected_results[emp_id]
        expected_rows.append(f"{emp_id},{total_hours},{total_cost}")

    expected_content = "\n".join(expected_rows)

    with open(summary_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {summary_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )


def test_cpp_program_compiles_and_generates_summary_from_inputs():
    source_path = "/home/user/process_data.cpp"
    employees_path = "/home/user/employees.csv"
    projects_path = "/home/user/projects.csv"
    summary_path = "/home/user/summary.csv"
    executable_path = "/tmp/process_data_verified"

    assert os.path.isfile(source_path), f"File {source_path} is missing."
    assert os.path.getsize(source_path) > 0, f"File {source_path} is empty."

    compile_errors = []
    compiled = False
    for standard in ("c++17", "c++14", "c++11"):
        result = subprocess.run(
            ["g++", f"-std={standard}", "-O2", source_path, "-o", executable_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            compiled = True
            break
        compile_errors.append(f"{standard}:\n{result.stderr}")

    assert compiled, "process_data.cpp did not compile:\n" + "\n".join(compile_errors)
    assert os.path.isfile(executable_path) and os.access(executable_path, os.X_OK)

    saved = {}
    for path in (employees_path, projects_path, summary_path):
        saved[path] = open(path, "rb").read() if os.path.exists(path) else None

    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    rng = random.SystemRandom()

    try:
        for case_number in range(2):
            count = 8 + case_number
            hierarchy_order = rng.sample(range(100, 10000), count)
            manager = {hierarchy_order[0]: None}
            for index in range(1, count):
                manager[hierarchy_order[index]] = rng.choice(hierarchy_order[:index])

            direct = {emp_id: [0, 0] for emp_id in hierarchy_order}
            project_rows = []
            for emp_id in hierarchy_order:
                assignments = 1 + rng.randrange(3)
                for project_index in range(assignments):
                    hours = rng.randrange(1, 200)
                    cost = rng.randrange(10, 20000)
                    direct[emp_id][0] += hours
                    direct[emp_id][1] += cost
                    project_rows.append([
                        emp_id,
                        f"Case{case_number}Project{project_index}_{emp_id}",
                        hours,
                        cost,
                    ])
            rng.shuffle(project_rows)

            with open(employees_path, "w", newline="") as f:
                writer = csv.writer(f, lineterminator="\n")
                writer.writerow(["emp_id", "name", "manager_id"])
                employee_rows = list(hierarchy_order)
                rng.shuffle(employee_rows)
                for emp_id in employee_rows:
                    manager_id = manager[emp_id]
                    writer.writerow([
                        emp_id,
                        f"Employee{emp_id}",
                        "" if manager_id is None else manager_id,
                    ])

            with open(projects_path, "w", newline="") as f:
                writer = csv.writer(f, lineterminator="\n")
                writer.writerow(["emp_id", "project_name", "hours", "cost"])
                writer.writerows(project_rows)

            children = defaultdict(list)
            for emp_id, manager_id in manager.items():
                if manager_id is not None:
                    children[manager_id].append(emp_id)

            def expected_rollup(emp_id):
                hours, cost = direct[emp_id]
                for child in children[emp_id]:
                    child_hours, child_cost = expected_rollup(child)
                    hours += child_hours
                    cost += child_cost
                return hours, cost

            expected_lines = ["emp_id,total_hours,total_cost"]
            for emp_id in sorted(hierarchy_order):
                hours, cost = expected_rollup(emp_id)
                expected_lines.append(f"{emp_id},{hours},{cost}")
            expected_content = "\n".join(expected_lines)

            if os.path.exists(summary_path):
                os.remove(summary_path)

            run = subprocess.run(
                [executable_path],
                cwd="/home/user",
                env={**os.environ, "HOME": "/home/user"},
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
                preexec_fn=demote,
            )
            assert run.returncode == 0, (
                f"Compiled program failed on verification input with exit code "
                f"{run.returncode}.\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"
            )
            assert os.path.isfile(summary_path), "The compiled program did not generate summary.csv."

            with open(summary_path, "r") as f:
                actual_content = f.read().strip()
            assert actual_content == expected_content, (
                "The compiled program produced an incorrect summary for verification input.\n"
                f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
            )
    finally:
        for path, content in saved.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
        if os.path.exists(executable_path):
            os.remove(executable_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
