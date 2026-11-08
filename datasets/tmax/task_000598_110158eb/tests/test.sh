#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import csv
import shutil
import subprocess
import tempfile
import pytest

DB_PATH = "/home/user/company.db"
CSV_PATH = "/home/user/high_earners.csv"
SCRIPT_PATH = "/home/user/analyze_org.sh"

@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    """Delete any prebuilt output and execute the submitted artifact."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable. Did you run chmod +x?"
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Script failed with exit code {result.returncode}: {result.stderr}"


def test_script_exists_and_executable():
    """Test if the analyze_org.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable. Did you run chmod +x?"


def test_csv_exists():
    """Test if the high_earners.csv file was generated."""
    assert os.path.isfile(CSV_PATH), f"CSV file not found at {CSV_PATH}. Make sure your script generates it."


def get_expected_data():
    """Helper to compute the expected data directly from the SQLite database."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    query = """
    WITH RECURSIVE org_chart AS (
        SELECT id, name, department, salary, manager_id, 0 AS depth
        FROM employees
        WHERE manager_id IS NULL
        UNION ALL
        SELECT e.id, e.name, e.department, e.salary, e.manager_id, o.depth + 1
        FROM employees e
        JOIN org_chart o ON e.manager_id = o.id
    ),
    dept_avgs AS (
        SELECT id, name, department, salary, depth,
               AVG(salary) OVER (PARTITION BY department) AS dept_avg_salary
        FROM org_chart
    )
    SELECT name, department, salary, depth, dept_avg_salary
    FROM dept_avgs
    WHERE depth >= 2 AND salary > dept_avg_salary
    ORDER BY depth DESC, salary DESC;
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()
    return rows


def assert_csv_contents():
    expected_rows = get_expected_data()

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("The CSV file is empty.")

        expected_header = ['name', 'department', 'salary', 'depth', 'dept_avg_salary']
        assert header == expected_header, f"CSV headers are incorrect. Expected {expected_header}, got {header}."

        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but found {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        row_num = i + 1
        assert len(actual) == 5, f"Row {row_num} does not have exactly 5 columns."

        assert actual[0] == expected['name'], f"Row {row_num}: expected name '{expected['name']}', got '{actual[0]}'."
        assert actual[1] == expected['department'], f"Row {row_num}: expected department '{expected['department']}', got '{actual[1]}'."

        try:
            actual_salary = int(actual[2])
        except ValueError:
            pytest.fail(f"Row {row_num}: salary '{actual[2]}' is not a valid integer.")
        assert actual_salary == expected['salary'], f"Row {row_num}: expected salary {expected['salary']}, got {actual_salary}."

        try:
            actual_depth = int(actual[3])
        except ValueError:
            pytest.fail(f"Row {row_num}: depth '{actual[3]}' is not a valid integer.")
        assert actual_depth == expected['depth'], f"Row {row_num}: expected depth {expected['depth']}, got {actual_depth}."

        try:
            actual_avg_salary = float(actual[4])
        except ValueError:
            pytest.fail(f"Row {row_num}: dept_avg_salary '{actual[4]}' is not a valid number.")

        expected_avg_salary = float(expected['dept_avg_salary'])
        assert abs(actual_avg_salary - expected_avg_salary) < 0.01, \
            f"Row {row_num}: expected dept_avg_salary {expected_avg_salary}, got {actual_avg_salary}."


def test_csv_contents():
    """Test if the CSV file contains the correct headers and data."""
    assert_csv_contents()


def test_script_recomputes_for_changed_database():
    """Ensure the script itself derives output instead of relying on a prebuilt CSV."""
    backup = tempfile.NamedTemporaryFile(delete=False)
    backup.close()
    shutil.copy2(DB_PATH, backup.name)

    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute("DELETE FROM employees")
        conn.executemany(
            "INSERT INTO employees (id, name, department, salary, manager_id) VALUES (?, ?, ?, ?, ?)",
            [
                (101, 'Root', 'Executive', 500000, None),
                (102, 'Eng Manager', 'Engineering', 210000, 101),
                (103, 'Sales Manager', 'Sales', 175000, 101),
                (104, 'Eng Junior', 'Engineering', 120000, 102),
                (105, 'Eng Senior', 'Engineering', 310000, 102),
                (106, 'Eng Deep', 'Engineering', 410000, 104),
                (107, 'Sales High', 'Sales', 260000, 103),
                (108, 'Sales Low', 'Sales', 55000, 103),
                (109, 'Eng Low Deep', 'Engineering', 70000, 104),
            ],
        )
        conn.commit()
        conn.close()

        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        result = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Script failed on changed database: {result.stderr}"
        assert os.path.isfile(CSV_PATH), f"CSV file not found at {CSV_PATH} after rerunning the script."
        assert_csv_contents()
    finally:
        shutil.copy2(backup.name, DB_PATH)
        os.remove(backup.name)
        if os.path.isfile(SCRIPT_PATH) and os.access(SCRIPT_PATH, os.X_OK):
            subprocess.run([SCRIPT_PATH], cwd="/home/user", timeout=15)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
