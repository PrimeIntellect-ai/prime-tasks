#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

SOURCE = "/home/user/graph_optimizer.cpp"
BINARY = "/home/user/graph_optimizer"
EMPLOYEES = "/home/user/employees.csv"
HIERARCHY = "/home/user/hierarchy.csv"
RESULTS = "/home/user/results.csv"

ORIGINAL_EMPLOYEES = """id,department,salary
1,Engineering,100000
2,Engineering,90000
3,Engineering,80000
4,HR,70000
5,HR,60000
6,Engineering,85000
7,Sales,120000
8,Sales,50000
9,Sales,50000
"""

ORIGINAL_HIERARCHY = """manager_id,employee_id
1,2
1,3
2,6
4,5
7,8
7,9
"""

EXPECTED_ORIGINAL = """id,department,subtree_avg_salary,dept_rank
1,Engineering,88750,1
2,Engineering,87500,2
6,Engineering,85000,3
3,Engineering,80000,4
4,HR,65000,1
5,HR,60000,2
7,Sales,73333,1
8,Sales,50000,2
9,Sales,50000,2"""


def normalized_lines(content):
    return [line.strip() for line in content.splitlines() if line.strip()]


def write_inputs(employees, edges):
    with open(EMPLOYEES, "w", newline="") as f:
        f.write("id,department,salary\n")
        for employee_id, department, salary in employees:
            f.write(f"{employee_id},{department},{salary}\n")

    with open(HIERARCHY, "w", newline="") as f:
        f.write("manager_id,employee_id\n")
        for manager_id, employee_id in edges:
            f.write(f"{manager_id},{employee_id}\n")


def run_submission():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"Submitted program exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULTS), f"Results file missing: {RESULTS}"
    with open(RESULTS, "r") as f:
        return f.read().strip()


def compute_expected(employees, edges):
    info = {employee_id: (department, salary)
            for employee_id, department, salary in employees}
    children = {employee_id: [] for employee_id in info}
    for manager_id, employee_id in edges:
        children[manager_id].append(employee_id)

    averages = {}
    visiting = set()

    def subtree(employee_id):
        assert employee_id not in visiting, "Generated test hierarchy contains a cycle"
        if employee_id in averages:
            # In these generated fixtures every employee has at most one manager.
            avg, total, count = averages[employee_id]
            return total, count
        visiting.add(employee_id)
        total = info[employee_id][1]
        count = 1
        for child_id in children[employee_id]:
            child_total, child_count = subtree(child_id)
            total += child_total
            count += child_count
        visiting.remove(employee_id)
        averages[employee_id] = (total // count, total, count)
        return total, count

    for employee_id in info:
        subtree(employee_id)

    ranks = {}
    departments = sorted({department for department, _ in info.values()})
    for department in departments:
        values = sorted(
            {averages[employee_id][0] for employee_id in info
             if info[employee_id][0] == department},
            reverse=True,
        )
        value_rank = {value: index + 1 for index, value in enumerate(values)}
        for employee_id in info:
            if info[employee_id][0] == department:
                ranks[employee_id] = value_rank[averages[employee_id][0]]

    rows = []
    for employee_id, (department, _) in info.items():
        rows.append((department, ranks[employee_id], employee_id,
                     averages[employee_id][0]))
    rows.sort(key=lambda row: (row[0], row[1], row[2]))

    lines = ["id,department,subtree_avg_salary,dept_rank"]
    for department, rank, employee_id, average in rows:
        lines.append(f"{employee_id},{department},{average},{rank}")
    return lines


@pytest.fixture(scope="session")
def compiled_program():
    completed = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert completed.returncode == 0, f"Compilation failed: {completed.stderr}"
    assert os.path.isfile(BINARY), f"Compiled program missing: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Compiled program is not executable: {BINARY}"
    return BINARY


def test_cpp_file_exists():
    file_path = SOURCE
    assert os.path.isfile(file_path), f"C++ source file missing: {file_path}"


def test_results_csv_exists_and_content(compiled_program):
    with open(EMPLOYEES, "w") as f:
        f.write(ORIGINAL_EMPLOYEES)
    with open(HIERARCHY, "w") as f:
        f.write(ORIGINAL_HIERARCHY)

    content = run_submission()
    file_path = RESULTS
    assert os.path.isfile(file_path), f"Results file missing: {file_path}"

    content_lines = normalized_lines(content)
    expected_lines = normalized_lines(EXPECTED_ORIGINAL)
    assert content_lines == expected_lines, (
        f"Content mismatch in {file_path}. Expected exactly the computed "
        "subtree average salaries and dense ranks."
    )


def test_program_handles_additional_hierarchies(compiled_program):
    rng = random.SystemRandom()
    departments = ["Alpha", "Engineering", "Operations", "Zeta"]

    for case_number in range(3):
        count = 11 + case_number * 2
        ids = rng.sample(range(1000, 9000), count)
        employees = []
        for index, employee_id in enumerate(ids):
            department = departments[(index + rng.randrange(len(departments))) % len(departments)]
            salary = rng.randrange(35001, 180000)
            employees.append((employee_id, department, salary))

        # Build a forest with arbitrary non-contiguous IDs and at most one manager
        # per employee. Force at least one multi-level reporting chain.
        edges = [(ids[0], ids[1]), (ids[1], ids[2])]
        for index in range(3, count):
            if rng.randrange(4) != 0:
                parent_index = rng.randrange(index)
                edges.append((ids[parent_index], ids[index]))

        rng.shuffle(employees)
        rng.shuffle(edges)
        write_inputs(employees, edges)
        expected_lines = compute_expected(employees, edges)
        actual_lines = normalized_lines(run_submission())
        assert actual_lines == expected_lines, (
            f"Program produced incorrect output for generated hierarchy case {case_number + 1}.\n"
            f"Expected: {expected_lines}\nActual: {actual_lines}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
