#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile


def test_c_source_file_exists():
    file_path = '/home/user/process_csv.c'
    assert os.path.isfile(file_path), f"C source file {file_path} is missing."


def test_c_executable_exists():
    file_path = '/home/user/process_csv'
    assert os.path.isfile(file_path), f"Compiled executable {file_path} is missing."
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."


def test_metrics_csv_exists_and_content():
    file_path = '/home/user/output/metrics.csv'
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    expected_content = """emp_id,subordinate_count,dept_avg_salary,dept_salary_rank
1,3,78750.00,1
2,1,78750.00,2
3,0,78750.00,3
4,0,78750.00,4
5,3,93750.00,1
6,1,93750.00,3
7,0,93750.00,2
8,0,93750.00,4"""

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, f"The content of {file_path} does not match the expected output. Got:\n{content}"


def expected_metrics(rows):
    by_id = {row[0]: row for row in rows}
    subordinate_count = {emp_id: 0 for emp_id in by_id}

    for emp_id, manager_id, salary, department in rows:
        seen = set()
        current = manager_id
        while current is not None:
            assert current in by_id, f"Invalid test hierarchy: missing manager {current}"
            assert current not in seen, "Invalid test hierarchy: cycle"
            seen.add(current)
            subordinate_count[current] += 1
            current = by_id[current][1]

    departments = {}
    for row in rows:
        departments.setdefault(row[3], []).append(row)

    averages = {}
    ranks = {}
    for department, members in departments.items():
        averages[department] = sum(row[2] for row in members) / len(members)
        ordered = sorted(members, key=lambda row: (-row[2], row[0]))
        for rank, row in enumerate(ordered, 1):
            ranks[row[0]] = rank

    lines = ['emp_id,subordinate_count,dept_avg_salary,dept_salary_rank']
    for emp_id, manager_id, salary, department in sorted(rows, key=lambda row: row[0]):
        lines.append(
            f'{emp_id},{subordinate_count[emp_id]},{averages[department]:.2f},{ranks[emp_id]}'
        )
    return '\n'.join(lines)


def write_input(path, rows):
    lines = ['emp_id,manager_id,salary,department']
    for emp_id, manager_id, salary, department in rows:
        manager = 'NULL' if manager_id is None else str(manager_id)
        lines.append(f'{emp_id},{manager},{salary},{department}')
    with open(path, 'w', newline='') as f:
        f.write('\n'.join(lines) + '\n')


def run_and_check(executable, rows):
    input_path = '/home/user/data/employees.csv'
    output_path = '/home/user/output/metrics.csv'
    write_input(input_path, rows)
    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert result.returncode == 0, (
        f'{executable} exited with {result.returncode}. stderr:\n{result.stderr}'
    )
    assert os.path.isfile(output_path), f'{executable} did not create {output_path}'

    with open(output_path, 'r') as f:
        actual = f.read().strip()
    expected = expected_metrics(rows)
    assert actual == expected, (
        f'Incorrect output from {executable}.\nExpected:\n{expected}\nGot:\n{actual}'
    )


def test_executable_and_compiled_source_process_inputs():
    source = '/home/user/process_csv.c'
    executable = '/home/user/process_csv'
    input_path = '/home/user/data/employees.csv'
    output_path = '/home/user/output/metrics.csv'

    with open(input_path, 'rb') as f:
        saved_input = f.read()
    with open(output_path, 'rb') as f:
        saved_output = f.read()

    with tempfile.TemporaryDirectory() as tmpdir:
        executable_backup = os.path.join(tmpdir, 'process_csv.backup')
        compiled = os.path.join(tmpdir, 'process_csv.compiled')
        shutil.copy2(executable, executable_backup)

        try:
            # Execute the submitted binary on the provided input and require it to
            # regenerate, rather than merely coexist with, the original output.
            provided_rows = [
                (1, None, 100000, 'Sales'),
                (2, 1, 80000, 'Sales'),
                (3, 1, 75000, 'Sales'),
                (4, 2, 60000, 'Sales'),
                (5, None, 120000, 'Engineering'),
                (6, 5, 90000, 'Engineering'),
                (7, 5, 95000, 'Engineering'),
                (8, 6, 70000, 'Engineering'),
            ]
            run_and_check(executable, provided_rows)

            # Compile the submitted C source, install that result at the required
            # executable path, and exercise it on independently derived cases.
            compile_result = subprocess.run(
                ['gcc', '-std=c11', '-O2', source, '-o', compiled],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=20
            )
            assert compile_result.returncode == 0, (
                f'Failed to compile {source}:\n{compile_result.stderr}'
            )
            os.replace(compiled, executable)

            edge_rows = [
                (99, 8, 70000, 'Beta'),
                (20, None, 90000, 'Alpha'),
                (77, 20, 50000, 'Gamma'),
                (5, 20, 90000, 'Alpha'),
                (2, 99, 50000, 'Beta'),
                (30, 5, 60000, 'Alpha'),
                (8, None, 70000, 'Beta'),
            ]
            run_and_check(executable, edge_rows)

            rng = random.Random(secrets.randbits(128))
            ids = rng.sample(range(101, 5000), 24)
            generated = []
            departments = ['North', 'South', 'Central', 'Support']
            salary_values = [50000, 60000, 70000, 80000, 90000]
            for index, emp_id in enumerate(ids):
                if index == 0:
                    manager_id = None
                elif index < 7:
                    manager_id = ids[index - 1]
                elif rng.randrange(5) == 0:
                    manager_id = None
                else:
                    manager_id = ids[rng.randrange(index)]
                generated.append([
                    emp_id,
                    manager_id,
                    rng.choice(salary_values),
                    rng.choice(departments),
                ])

            # Guarantee a salary tie whose rank is resolved by emp_id.
            generated[0][2] = 90000
            generated[0][3] = 'North'
            generated[1][2] = 90000
            generated[1][3] = 'North'
            rng.shuffle(generated)
            run_and_check(executable, [tuple(row) for row in generated])
        finally:
            with open(input_path, 'wb') as f:
                f.write(saved_input)
            with open(output_path, 'wb') as f:
                f.write(saved_output)
            shutil.copy2(executable_backup, executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
