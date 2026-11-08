#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import io
import json
import re
import secrets
import sqlite3
import subprocess
import pytest

REPORT_PATH = "/home/user/report.csv"
QUERY_PATH = "/home/user/query.sql"
DB_PATH = "/home/user/company.db"


def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."


def test_report_content():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    # Recompute expected data from the database
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    query = """
    WITH RECURSIVE subordinates AS (
        SELECT emp_id FROM org_chart WHERE emp_id = 1
        UNION ALL
        SELECT o.emp_id FROM org_chart o
        INNER JOIN subordinates s ON o.manager_id = s.emp_id
    ),
    sales_events AS (
        SELECT 
            e.emp_id,
            json_extract(e.payload, '$.timestamp') as event_timestamp,
            CAST(json_extract(e.payload, '$.amount') AS NUMERIC) as sale_amount
        FROM events e
        INNER JOIN subordinates s ON e.emp_id = s.emp_id
        WHERE json_extract(e.payload, '$.type') = 'sale'
    )
    SELECT 
        emp_id,
        event_timestamp,
        sale_amount,
        SUM(sale_amount) OVER (PARTITION BY emp_id ORDER BY event_timestamp ASC) as cumulative_sales
    FROM sales_events
    ORDER BY emp_id ASC, event_timestamp ASC;
    """

    cursor.execute(query)
    expected_rows = cursor.fetchall()
    conn.close()

    # Format expected rows as strings to match CSV reading
    expected_csv_rows = []
    for row in expected_rows:
        expected_csv_rows.append([str(row[0]), str(row[1]), str(row[2]), str(row[3])])

    expected_header = ["emp_id", "event_timestamp", "sale_amount", "cumulative_sales"]

    # Read the generated CSV
    actual_csv_rows = []
    with open(REPORT_PATH, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            actual_header = next(reader)
        except StopIteration:
            pytest.fail("The generated CSV file is empty.")

        for row in reader:
            if any(row):  # skip empty rows
                actual_csv_rows.append(row)

    assert actual_header == expected_header, f"CSV header mismatch. Expected {expected_header}, got {actual_header}."

    assert len(actual_csv_rows) == len(expected_csv_rows), f"CSV row count mismatch. Expected {len(expected_csv_rows)} data rows, got {len(actual_csv_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_csv_rows, expected_csv_rows)):
        assert actual == expected, f"Data row {i+1} mismatch. Expected {expected}, got {actual}."


def read_query():
    assert os.path.exists(QUERY_PATH), f"SQL query file {QUERY_PATH} is missing."
    assert os.path.isfile(QUERY_PATH), f"{QUERY_PATH} is not a file."
    with open(QUERY_PATH, "r", encoding="utf-8") as f:
        sql = f.read()
    assert sql.strip(), f"SQL query file {QUERY_PATH} is empty."
    return sql


def sql_without_cli_commands(sql):
    # The submitted artifact may contain sqlite3 export commands such as
    # .headers, .mode, and .output. The verifier supplies its own CSV output
    # settings while executing the actual SQL against a private test database.
    return "\n".join(
        line for line in sql.splitlines()
        if not line.lstrip().startswith(".")
    )


def test_query_artifact_uses_required_sql_features():
    sql = read_query()
    pure_sql = sql_without_cli_commands(sql)

    # Ignore comments and quoted literals so merely mentioning keywords in a
    # comment or string does not satisfy the artifact checks.
    structural = re.sub(r"/\*.*?\*/", " ", pure_sql, flags=re.S)
    structural = re.sub(r"--[^\n]*", " ", structural)
    structural = re.sub(r"'(?:''|[^'])*'", "''", structural)
    structural = re.sub(r'"(?:""|[^"])*"', '""', structural)

    assert re.search(r"\bWITH\s+RECURSIVE\b", structural, re.I), \
        "query.sql must use a recursive CTE for the employee subtree."
    assert re.search(r"\bOVER\s*\(", structural, re.I), \
        "query.sql must use a window function for cumulative sales."
    assert re.search(r"\bJSON_EXTRACT\s*\(|->>?", structural, re.I), \
        "query.sql must extract fields from the JSON payload."


def test_query_executes_generically_on_private_database(tmp_path):
    submitted = sql_without_cli_commands(read_query())
    assert submitted.strip(), "query.sql contains no executable SQL."

    test_db = tmp_path / "company_private.db"
    conn = sqlite3.connect(test_db)
    conn.executescript("""
        CREATE TABLE org_chart (emp_id INTEGER PRIMARY KEY, manager_id INTEGER);
        CREATE TABLE events (event_id INTEGER PRIMARY KEY, emp_id INTEGER, payload TEXT);
    """)

    # Use unpredictable employee IDs and amounts so a precomputed report or a
    # query tied to the image's original rows cannot pass this execution test.
    ids = set()
    while len(ids) < 4:
        ids.add(secrets.randbelow(800000) + 10000)
    direct, deep, deeper, outsider = list(ids)
    amounts = [secrets.randbelow(800) + 11 for _ in range(5)]

    conn.executemany(
        "INSERT INTO org_chart(emp_id, manager_id) VALUES (?, ?)",
        [
            (9000001, None),
            (1, 9000001),
            (direct, 1),
            (deep, direct),
            (deeper, deep),
            (outsider, 9000001),
        ],
    )

    events = [
        (1, 1, {"type": "sale", "amount": amounts[0], "timestamp": "2041-03-02T08:00:00"}),
        (2, direct, {"type": "sale", "amount": amounts[1], "timestamp": "2041-03-03T10:00:00"}),
        (3, direct, {"type": "sale", "amount": amounts[2], "timestamp": "2041-03-01T10:00:00"}),
        (4, deep, {"type": "lead", "amount": 999999, "timestamp": "2041-03-01T07:00:00"}),
        (5, deep, {"type": "sale", "amount": amounts[3], "timestamp": "2041-03-04T09:30:00"}),
        (6, deeper, {"type": "sale", "amount": amounts[4], "timestamp": "2041-03-05T11:00:00"}),
        (7, outsider, {"type": "sale", "amount": 888888, "timestamp": "2041-03-01T06:00:00"}),
    ]
    conn.executemany(
        "INSERT INTO events(event_id, emp_id, payload) VALUES (?, ?, ?)",
        [(event_id, emp_id, json.dumps(payload)) for event_id, emp_id, payload in events],
    )
    conn.commit()

    reference = """
    WITH RECURSIVE subordinates AS (
        SELECT emp_id FROM org_chart WHERE emp_id = 1
        UNION ALL
        SELECT o.emp_id
        FROM org_chart o
        INNER JOIN subordinates s ON o.manager_id = s.emp_id
    ),
    sales_events AS (
        SELECT e.emp_id,
               json_extract(e.payload, '$.timestamp') AS event_timestamp,
               CAST(json_extract(e.payload, '$.amount') AS NUMERIC) AS sale_amount
        FROM events e
        INNER JOIN subordinates s ON e.emp_id = s.emp_id
        WHERE json_extract(e.payload, '$.type') = 'sale'
    )
    SELECT emp_id, event_timestamp, sale_amount,
           SUM(sale_amount) OVER (
               PARTITION BY emp_id ORDER BY event_timestamp ASC
           ) AS cumulative_sales
    FROM sales_events
    ORDER BY emp_id ASC, event_timestamp ASC;
    """
    expected_rows = [
        [str(value) for value in row]
        for row in conn.execute(reference).fetchall()
    ]
    conn.close()

    result = subprocess.run(
        ["sqlite3", "-header", "-csv", str(test_db)],
        input=submitted,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, \
        f"query.sql failed when executed against a compatible database: {result.stderr}"

    reader = csv.reader(io.StringIO(result.stdout))
    rows = list(reader)
    assert rows, "Executing query.sql produced no result set."
    expected_header = ["emp_id", "event_timestamp", "sale_amount", "cumulative_sales"]
    assert rows[0] == expected_header, \
        f"Executed query header mismatch. Expected {expected_header}, got {rows[0]}."
    assert rows[1:] == expected_rows, \
        f"query.sql returned incorrect results on a private database. Expected {expected_rows}, got {rows[1:]}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
