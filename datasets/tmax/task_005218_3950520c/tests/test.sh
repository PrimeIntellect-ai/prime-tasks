#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = "/home/user/audit.db"
REPORT_PATH = "/home/user/suspicious_report.json"
PROJECT_PATH = "/home/user/audit_tool"
CARGO_TOML_PATH = os.path.join(PROJECT_PATH, "Cargo.toml")
MAIN_RS_PATH = os.path.join(PROJECT_PATH, "src/main.rs")

EXPECTED_QUERY = """
WITH EmployeeTotals AS (
    SELECT e.id, e.name, e.manager_id, SUM(ex.amount) as total_spent
    FROM employees e
    JOIN expenses ex ON e.id = ex.emp_id
    GROUP BY e.id, e.name, e.manager_id
),
Ranked AS (
    SELECT name as employee_name, manager_id, total_spent,
           RANK() OVER (PARTITION BY manager_id ORDER BY total_spent DESC) as team_rank
    FROM EmployeeTotals
    WHERE manager_id IS NOT NULL
)
SELECT employee_name, manager_id, total_spent, team_rank
FROM Ranked
WHERE team_rank <= 2 AND total_spent > 10000.0
ORDER BY manager_id ASC, total_spent DESC;
"""


def run_application():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", CARGO_TOML_PATH],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=240,
    )
    assert result.returncode == 0, (
        "Rust application failed to build or run.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), "Running the Rust application did not create the report"


def load_report():
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Report file is not valid JSON")


def expected_rows():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        return [dict(row) for row in conn.execute(EXPECTED_QUERY).fetchall()]
    finally:
        conn.close()


def assert_report_matches(data, expected):
    assert isinstance(data, list), "JSON output must be an array of objects"
    assert len(data) == len(expected), (
        f"Expected {len(expected)} records in the report, but found {len(data)}."
    )
    required_keys = {"employee_name", "manager_id", "total_spent", "team_rank"}
    for i, (actual, wanted) in enumerate(zip(data, expected)):
        assert isinstance(actual, dict), f"Record {i} must be a JSON object"
        assert set(actual.keys()) == required_keys, (
            f"Record {i} must contain exactly the keys {sorted(required_keys)}"
        )
        assert actual.get("employee_name") == wanted["employee_name"], (
            f"Record {i}: Expected employee_name '{wanted['employee_name']}', "
            f"got '{actual.get('employee_name')}'"
        )
        assert actual.get("manager_id") == wanted["manager_id"], (
            f"Record {i}: Expected manager_id {wanted['manager_id']}, "
            f"got {actual.get('manager_id')}"
        )
        assert float(actual.get("total_spent", 0)) == float(wanted["total_spent"]), (
            f"Record {i}: Expected total_spent {wanted['total_spent']}, "
            f"got {actual.get('total_spent')}"
        )
        assert actual.get("team_rank") == wanted["team_rank"], (
            f"Record {i}: Expected team_rank {wanted['team_rank']}, "
            f"got {actual.get('team_rank')}"
        )


def test_rust_project_exists():
    """Verify that the Cargo project was created in the correct location."""
    assert os.path.isfile(CARGO_TOML_PATH), f"Cargo.toml missing at {CARGO_TOML_PATH}"
    assert os.path.isfile(MAIN_RS_PATH), "Rust source file missing at /home/user/audit_tool/src/main.rs"


def test_rust_source_contains_required_window_query():
    """Verify the submitted Rust project contains the required analytical SQL."""
    source_parts = []
    for root, _, files in os.walk(os.path.join(PROJECT_PATH, "src")):
        for filename in files:
            if filename.endswith((".rs", ".sql")):
                with open(os.path.join(root, filename), "r", errors="replace") as f:
                    source_parts.append(f.read())
    source = "\n".join(source_parts)
    assert re.search(r"\bSUM\s*\(", source, re.IGNORECASE), "SQL must aggregate employee expenses with SUM"
    assert re.search(r"\b(RANK|DENSE_RANK|ROW_NUMBER)\s*\(\s*\)\s*OVER\s*\(", source, re.IGNORECASE | re.DOTALL), (
        "SQL must use a window ranking function"
    )
    assert re.search(r"\bPARTITION\s+BY\s+[^\n;]*manager_id", source, re.IGNORECASE), (
        "Window ranking must be partitioned by manager_id"
    )
    assert re.search(r"\bORDER\s+BY\s+[^\n;]*total_spent\s+DESC", source, re.IGNORECASE), (
        "Window ranking must order total_spent descending"
    )


def test_application_builds_and_runs():
    """Build and execute the submitted Cargo application rather than trusting a prewritten report."""
    run_application()


def test_json_report_exists_and_valid():
    """Verify that the report file exists and is valid JSON."""
    assert os.path.isfile(REPORT_PATH), f"Report file missing at {REPORT_PATH}"
    data = load_report()
    assert isinstance(data, list), "JSON output must be an array of objects"


def test_json_report_contents():
    """Verify the contents of the JSON report match the expected database query results."""
    assert os.path.isfile(REPORT_PATH), "Report file missing"
    data = load_report()
    assert_report_matches(data, expected_rows())


def test_application_queries_changed_database_dynamically():
    """Replace the fixed fixture temporarily and require a newly generated, dynamically correct report."""
    fd, backup_path = tempfile.mkstemp(prefix="audit-db-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    old_report = None
    if os.path.exists(REPORT_PATH):
        with open(REPORT_PATH, "rb") as f:
            old_report = f.read()

    token = secrets.token_hex(8)
    base = 100000 + secrets.randbelow(700000)
    bump = secrets.randbelow(500)
    employees = [
        (base, f"ceo_{token}", None),
        (base + 10, f"manager_a_{token}", base),
        (base + 20, f"manager_b_{token}", base),
        (base + 101, f"alpha_{token}", base + 10),
        (base + 102, f"beta_{token}", base + 10),
        (base + 103, f"third_{token}", base + 10),
        (base + 201, f"boundary_{token}", base + 20),
        (base + 202, f"below_{token}", base + 20),
    ]
    expenses = [
        (base + 1, base + 101, 17000.0 + bump, "2026-01-01"),
        (base + 2, base + 101, 16000.0, "2026-01-02"),
        (base + 3, base + 102, 24000.0 + bump, "2026-01-03"),
        (base + 4, base + 103, 15000.0 + bump, "2026-01-04"),
        (base + 5, base + 201, 10000.0, "2026-01-05"),
        (base + 6, base + 202, 9999.0, "2026-01-06"),
    ]

    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("DELETE FROM expenses")
            conn.execute("DELETE FROM employees")
            conn.executemany("INSERT INTO employees(id, name, manager_id) VALUES (?, ?, ?)", employees)
            conn.executemany(
                "INSERT INTO expenses(id, emp_id, amount, timestamp) VALUES (?, ?, ?, ?)",
                expenses,
            )
            conn.commit()
        finally:
            conn.close()

        wanted = expected_rows()
        run_application()
        assert_report_matches(load_report(), wanted)
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
        if old_report is not None:
            with open(REPORT_PATH, "wb") as f:
                f.write(old_report)
        elif os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
