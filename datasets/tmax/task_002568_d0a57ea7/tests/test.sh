#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import re
import secrets
import string
import subprocess

SCRIPT_PATH = "/home/user/hierarchy_sales.py"
OUTPUT_PATH = "/home/user/output.csv"
EMPLOYEES_PATH = "/home/user/data/employees.csv"
SALES_PATH = "/home/user/data/sales.csv"


def run_script(limit, offset):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH, str(limit), str(offset)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Script failed to execute. Error:\n{result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r", newline="", encoding="utf-8") as f:
        return list(csv.reader(f))


def test_script_exists():
    """Check if the hierarchy_sales.py script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."


def test_uses_sqlite_recursive_query():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    imports_sqlite = any(
        (isinstance(node, ast.Import) and any(alias.name == "sqlite3" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "sqlite3")
        or (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "__import__"
            and node.args
            and isinstance(node.args[0], ast.Constant)
            and node.args[0].value == "sqlite3"
        )
        for node in ast.walk(tree)
    )
    assert imports_sqlite, "The script must use the sqlite3 standard library module."

    literal_text = " ".join(
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    )
    assert re.search(r"\bWITH\s+RECURSIVE\b", literal_text, re.IGNORECASE), \
        "The script must contain and execute a WITH RECURSIVE SQL query."


def test_script_execution_and_output_3_1():
    """Run the script with limit 3 and offset 1, and verify the output."""
    result = subprocess.run(
        ["python3", SCRIPT_PATH, "3", "1"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed to execute. Error:\n{result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r", newline="") as f:
        reader = list(csv.reader(f))

    expected_output = [
        ["id", "name", "total_sales"],
        ["3", "Charlie", "10000"],
        ["2", "Bob", "8000"],
        ["6", "Frank", "6500"]
    ]
    assert reader == expected_output, f"Output CSV content is incorrect for limit 3, offset 1. Got: {reader}"


def test_script_execution_and_output_2_0():
    """Run the script with limit 2 and offset 0 to ensure pagination is dynamic."""
    result = subprocess.run(
        ["python3", SCRIPT_PATH, "2", "0"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed to execute. Error:\n{result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r", newline="") as f:
        reader = list(csv.reader(f))

    expected_output = [
        ["id", "name", "total_sales"],
        ["1", "Alice", "19000"],
        ["3", "Charlie", "10000"]
    ]
    assert reader == expected_output, f"Output CSV content is incorrect for limit 2, offset 0. Got: {reader}"


def test_randomized_input_files_and_pagination():
    rng = secrets.SystemRandom()
    original_employees = open(EMPLOYEES_PATH, "rb").read()
    original_sales = open(SALES_PATH, "rb").read()

    try:
        ids = rng.sample(range(100, 5000), 22)
        token = "".join(rng.choice(string.ascii_letters) for _ in range(10))
        names = {eid: f'Employee {i}, "{token}-{i}"' for i, eid in enumerate(ids)}

        managers = {ids[0]: None}
        for i in range(1, 6):
            managers[ids[i]] = ids[0]
        managers[ids[6]] = ids[0]
        managers[ids[7]] = ids[0]
        for i in range(8, 13):
            managers[ids[i]] = ids[rng.randrange(1, 6)]
        for i in range(13, 21):
            managers[ids[i]] = ids[rng.randrange(8, 13)]
        managers[ids[21]] = ids[rng.randrange(13, 21)]

        amounts = {eid: rng.randrange(200, 3501) for eid in ids}
        amounts[ids[6]] = 6000
        amounts[ids[7]] = 6000
        amounts[ids[21]] = 5000

        employee_rows = ids[:]
        sales_rows = ids[:]
        rng.shuffle(employee_rows)
        rng.shuffle(sales_rows)

        with open(EMPLOYEES_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "name", "manager_id"])
            for eid in employee_rows:
                manager = "" if managers[eid] is None else managers[eid]
                writer.writerow([eid, names[eid], manager])

        with open(SALES_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "amount"])
            for eid in sales_rows:
                writer.writerow([eid, amounts[eid]])

        totals = dict(amounts)
        for eid in ids:
            ancestor = managers[eid]
            while ancestor is not None:
                totals[ancestor] += amounts[eid]
                ancestor = managers[ancestor]

        filtered = sorted(
            (eid for eid in ids if totals[eid] >= 5000),
            key=lambda eid: (-totals[eid], eid),
        )

        pairs = [
            (len(filtered) + 5, 0),
            (4, 2),
            (rng.randrange(1, 7), rng.randrange(0, len(filtered) + 3)),
        ]
        for limit, offset in pairs:
            page = filtered[offset:offset + limit]
            expected = [["id", "name", "total_sales"]] + [
                [str(eid), names[eid], str(totals[eid])] for eid in page
            ]
            actual = run_script(limit, offset)
            assert actual == expected, (
                f"Output CSV content is incorrect for randomized data with "
                f"limit={limit}, offset={offset}. Got: {actual}; expected: {expected}"
            )
    finally:
        with open(EMPLOYEES_PATH, "wb") as f:
            f.write(original_employees)
        with open(SALES_PATH, "wb") as f:
            f.write(original_sales)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
