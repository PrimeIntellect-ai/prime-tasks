#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess
import time
import urllib.request

import pandas as pd
import pytest

ETL_SCRIPT = "/home/user/etl.sh"
OUTPUT_CSV = "/home/user/total_salaries.csv"
API_LOG = "/var/log/api.log"


def run_as_postgres(sql, database="postgres"):
    return subprocess.run(
        ["runuser", "-u", "postgres", "--", "psql", "-X", "-v", "ON_ERROR_STOP=1", "-At", "-d", database, "-c", sql],
        text=True,
        capture_output=True,
        timeout=20,
    )


def fetch_api_data():
    employees = []
    page = 1
    while page is not None:
        with urllib.request.urlopen(
            f"http://localhost:5000/api/employees?page={page}", timeout=5
        ) as response:
            payload = json.load(response)
        employees.extend(payload["data"])
        page = payload["next_page"]
    return employees


def expected_totals(employees):
    by_id = {int(row["id"]): row for row in employees}
    children = {employee_id: [] for employee_id in by_id}
    for row in employees:
        manager_id = row["manager_id"]
        if manager_id is not None:
            children[int(manager_id)].append(int(row["id"]))

    visiting = set()
    memo = {}

    def total(employee_id):
        if employee_id in memo:
            return memo[employee_id]
        assert employee_id not in visiting, "API hierarchy contains a cycle"
        visiting.add(employee_id)
        value = int(by_id[employee_id]["salary"])
        value += sum(total(child) for child in children[employee_id])
        visiting.remove(employee_id)
        memo[employee_id] = value
        return value

    return [(employee_id, total(employee_id)) for employee_id in sorted(by_id)]


@pytest.fixture(scope="session", autouse=True)
def execute_etl():
    assert os.path.isfile(ETL_SCRIPT), f"Expected ETL script not found at {ETL_SCRIPT}"
    assert os.access(ETL_SCRIPT, os.X_OK), f"ETL script {ETL_SCRIPT} is not executable"

    with open(ETL_SCRIPT, "r", encoding="utf-8", errors="replace") as handle:
        script_text = handle.read()
    assert "/app/start_services.sh" in script_text, "ETL script must start the provided services"
    assert re.search(r"\bpsql\b", script_text), "ETL script must use PostgreSQL"
    assert "/api/employees" in script_text, "ETL script must extract from the employee API"

    # Establish a known service state, then remove the prior database and output so
    # verification exercises the submitted workflow rather than trusting artifacts
    # left by the agent's earlier run.
    prep = subprocess.run(
        ["/app/start_services.sh"], text=True, capture_output=True, timeout=30
    )
    assert prep.returncode == 0, prep.stdout + prep.stderr

    terminated = run_as_postgres(
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
        "WHERE datname = 'org_db' AND pid <> pg_backend_pid();"
    )
    assert terminated.returncode == 0, terminated.stdout + terminated.stderr
    dropped = run_as_postgres("DROP DATABASE IF EXISTS org_db;")
    assert dropped.returncode == 0, dropped.stdout + dropped.stderr

    if os.path.exists(OUTPUT_CSV):
        os.remove(OUTPUT_CSV)
    with open(API_LOG, "w", encoding="utf-8"):
        pass

    result = subprocess.run(
        [ETL_SCRIPT], text=True, capture_output=True, timeout=90
    )
    assert result.returncode == 0, (
        f"ETL script failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    time.sleep(0.5)

    # Ensure extraction traversed both pages before the verifier itself accesses
    # the API to derive the expected result.
    with open(API_LOG, "r", encoding="utf-8", errors="replace") as handle:
        api_log = handle.read()
    assert re.search(r"GET /api/employees\?page=1(?:\s| HTTP)", api_log), "ETL did not request API page 1"
    assert re.search(r"GET /api/employees\?page=2(?:\s| HTTP)", api_log), "ETL did not request API page 2"


def test_etl_script_exists_and_executable():
    assert os.path.isfile(ETL_SCRIPT), f"Expected ETL script not found at {ETL_SCRIPT}"
    assert os.access(ETL_SCRIPT, os.X_OK), f"ETL script {ETL_SCRIPT} is not executable"


def test_output_csv_exists():
    assert os.path.isfile(OUTPUT_CSV), f"Expected output CSV not found at {OUTPUT_CSV}"


def test_employee_data_was_loaded_into_postgresql():
    employees = fetch_api_data()
    expected = sorted(
        (int(row["id"]), None if row["manager_id"] is None else int(row["manager_id"]), int(row["salary"]))
        for row in employees
    )

    tables_result = run_as_postgres(
        "SELECT c.table_schema || E'\\t' || c.table_name "
        "FROM information_schema.columns c "
        "WHERE c.table_schema NOT IN ('pg_catalog','information_schema') "
        "GROUP BY c.table_schema, c.table_name "
        "HAVING bool_or(c.column_name='id') "
        "AND bool_or(c.column_name='manager_id') "
        "AND bool_or(c.column_name='salary');",
        database="org_db",
    )
    assert tables_result.returncode == 0, tables_result.stdout + tables_result.stderr

    matching_table = False
    for line in tables_result.stdout.splitlines():
        if not line.strip():
            continue
        schema, table = line.split("\t", 1)
        quoted_schema = '"' + schema.replace('"', '""') + '"'
        quoted_table = '"' + table.replace('"', '""') + '"'
        query = (
            f"SELECT id::text, COALESCE(manager_id::text, ''), salary::text "
            f"FROM {quoted_schema}.{quoted_table} ORDER BY id;"
        )
        rows_result = run_as_postgres(query, database="org_db")
        if rows_result.returncode != 0:
            continue
        try:
            actual = []
            for row in rows_result.stdout.splitlines():
                employee_id, manager_id, salary = row.split("|")
                actual.append((int(employee_id), None if manager_id == "" else int(manager_id), int(salary)))
        except (ValueError, TypeError):
            continue
        if actual == expected:
            matching_table = True
            break

    assert matching_table, "No PostgreSQL table contains the complete employee data extracted from the API"


def test_total_salaries_accuracy():
    assert os.path.isfile(OUTPUT_CSV), "Output CSV is missing."
    employees = fetch_api_data()
    expected = expected_totals(employees)

    try:
        pred = pd.read_csv(OUTPUT_CSV, header=None, names=['id', 'total_salary'])
    except Exception as exc:
        pytest.fail(f"Failed to read output CSV: {exc}")

    assert len(pred) == len(expected), f"Row count mismatch: expected {len(expected)}, got {len(pred)}"
    truth = pd.DataFrame(expected, columns=['id', 'total_salary'])
    pred_sorted = pred.sort_values('id').reset_index(drop=True)
    truth_sorted = truth.sort_values('id').reset_index(drop=True)
    matches = (pred_sorted['total_salary'] == truth_sorted['total_salary']).sum()
    accuracy = matches / len(truth_sorted)
    assert accuracy >= 1.0, f"Accuracy is {accuracy:.4f}, expected >= 1.0. Some total salaries are incorrect."

    # Also enforce the required IDs, ordering, two-column shape, and absence of a header.
    with open(OUTPUT_CSV, newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    assert all(len(row) == 2 for row in rows), "CSV must have exactly two columns"
    try:
        actual_exact = [(int(row[0]), int(row[1])) for row in rows]
    except ValueError as exc:
        pytest.fail(f"CSV must contain numeric IDs and salaries with no header: {exc}")
    assert actual_exact == expected, "CSV IDs, totals, or ascending ID order are incorrect"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
