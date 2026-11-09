#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile

EMPLOYEES = "/home/user/employees.csv"
SALES = "/home/user/sales.csv"
SOURCE = "/home/user/aggregate.cpp"
BINARY = "/home/user/aggregate"
TOTAL = "/home/user/total_sales.csv"
QUERY = "/home/user/query_result.txt"


def test_total_sales_csv_content():
    assert os.path.isfile(TOTAL), f"Output file {TOTAL} does not exist. Did you run the program?"

    with open(TOTAL, "r") as f:
        content = f.read().strip()

    expected_content = """emp_id,total_sales
1,1350
2,550
3,700
4,300
5,50
6,550
7,150"""

    assert content == expected_content, f"Content of {TOTAL} does not match the expected aggregated sales data."


def test_query_result_txt_content():
    assert os.path.isfile(QUERY), f"Output file {QUERY} does not exist. Did you run the program with --target-id 2?"

    with open(QUERY, "r") as f:
        content = f.read().strip()

    assert content == "550", f"Content of {QUERY} does not match the expected query result for Employee 2. Expected '550', got '{content}'."


def test_source_and_binary_exist():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {BINARY} is not a compiled executable."


def make_case(rng, count):
    ids = rng.sample(range(10, 1000), count)
    parents = {ids[0]: None}
    for i in range(1, count):
        parents[ids[i]] = rng.choice(ids[:i])

    employee_rows = [(emp_id, f"Employee{emp_id}", parents[emp_id]) for emp_id in ids]
    rng.shuffle(employee_rows)

    own_sales = {emp_id: 0 for emp_id in ids}
    sale_rows = []
    for emp_id in ids:
        for _ in range(rng.randint(1, 3)):
            amount = rng.randint(1, 900)
            own_sales[emp_id] += amount
            sale_rows.append((emp_id, amount))
    rng.shuffle(sale_rows)

    children = {emp_id: [] for emp_id in ids}
    for emp_id, manager_id in parents.items():
        if manager_id is not None:
            children[manager_id].append(emp_id)

    totals = {}

    def aggregate(emp_id):
        value = own_sales[emp_id]
        for child in children[emp_id]:
            value += aggregate(child)
        totals[emp_id] = value
        return value

    aggregate(ids[0])
    return employee_rows, sale_rows, totals, rng.choice(ids)


def write_case(employee_rows, sale_rows):
    with open(EMPLOYEES, "w", newline="") as f:
        f.write("emp_id,emp_name,manager_id\n")
        for emp_id, name, manager_id in employee_rows:
            manager = "NULL" if manager_id is None else str(manager_id)
            f.write(f"{emp_id},{name},{manager}\n")

    with open(SALES, "w", newline="") as f:
        f.write("emp_id,sale_amount\n")
        for emp_id, amount in sale_rows:
            f.write(f"{emp_id},{amount}\n")


def expected_csv(totals):
    lines = ["emp_id,total_sales"]
    lines.extend(f"{emp_id},{totals[emp_id]}" for emp_id in sorted(totals))
    return "\n".join(lines)


def run_and_check(executable, totals, target):
    for path in (TOTAL, QUERY):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run([executable], cwd="/home/user", stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0, f"{executable} failed without arguments: {result.stderr}"
    assert os.path.isfile(TOTAL), f"{executable} did not generate {TOTAL}"
    with open(TOTAL, "r") as f:
        actual = f.read().strip()
    assert actual == expected_csv(totals), f"{executable} produced incorrect dynamically aggregated CSV"

    if os.path.exists(QUERY):
        os.remove(QUERY)
    result = subprocess.run([executable, "--target-id", str(target)], cwd="/home/user",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0, f"{executable} failed for --target-id {target}: {result.stderr}"
    assert os.path.isfile(TOTAL), f"{executable} did not generate {TOTAL} during a target query"
    with open(TOTAL, "r") as f:
        actual = f.read().strip()
    assert actual == expected_csv(totals), f"{executable} produced incorrect CSV during a target query"
    assert os.path.isfile(QUERY), f"{executable} did not generate {QUERY} for --target-id"
    with open(QUERY, "r") as f:
        query_value = f.read().strip()
    assert query_value == str(totals[target]), f"Incorrect query result for dynamically selected employee {target}"


def test_program_executes_dynamic_aggregation_and_query():
    paths = (EMPLOYEES, SALES, TOTAL, QUERY)
    backups = {}
    for path in paths:
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    rebuilt_fd, rebuilt = tempfile.mkstemp(prefix="aggregate_rebuilt_", dir="/tmp")
    os.close(rebuilt_fd)
    os.remove(rebuilt)

    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_result.returncode == 0, f"aggregate.cpp does not compile as required: {compile_result.stderr}"

        rng = random.Random(secrets.randbits(128))
        for count in (6, 9):
            employee_rows, sale_rows, totals, target = make_case(rng, count)
            write_case(employee_rows, sale_rows)
            run_and_check(BINARY, totals, target)
            run_and_check(rebuilt, totals, target)
    finally:
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
