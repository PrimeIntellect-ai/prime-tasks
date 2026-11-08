#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
from pathlib import Path

import pytest

DB_PATH = "/home/user/compliance.db"
REPORT_PATH = "/home/user/audit_report.json"
PROJECT_PATH = Path("/home/user/audit_tool")


def assert_database_indexes():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_employee_assets';")
    old_index = cursor.fetchone()
    assert old_index is None, "The index 'idx_employee_assets' was not dropped."

    cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND name='idx_assets_emp_val';")
    new_index = cursor.fetchone()
    assert new_index is not None, "The index 'idx_assets_emp_val' was not created."

    sql = new_index[1].lower()
    assert "employee_id" in sql, "The new index must cover 'employee_id'."
    assert "value" in sql, "The new index must cover 'value'."
    assert "desc" in sql, "The new index must sort 'value' in DESC order."

    conn.close()


def test_01_database_indexes():
    """Verify that the old index is dropped and the new index is created correctly."""
    assert_database_indexes()


def test_02_json_report():
    """Verify the generated JSON report exists and contains the correct data."""
    assert os.path.exists(REPORT_PATH), f"Report file missing at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file audit_report.json is not valid JSON.")

    expected_data = [
        {"employee_id": 2, "name": "Bob", "total_asset_value": 6000, "asset_count": 2},
        {"employee_id": 6, "name": "Frank", "total_asset_value": 2500, "asset_count": 2},
        {"employee_id": 1, "name": "Alice", "total_asset_value": 2000, "asset_count": 1},
        {"employee_id": 3, "name": "Charlie", "total_asset_value": 1500, "asset_count": 1},
        {"employee_id": 4, "name": "Diana", "total_asset_value": 500, "asset_count": 1},
        {"employee_id": 5, "name": "Eve", "total_asset_value": 0, "asset_count": 0}
    ]

    assert isinstance(report_data, list), "The JSON report must be a list of objects."
    assert len(report_data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(report_data)}."

    for i, (actual, expected) in enumerate(zip(report_data, expected_data)):
        assert actual.get("employee_id") == expected["employee_id"], f"Record {i}: expected employee_id {expected['employee_id']}, got {actual.get('employee_id')}"
        assert actual.get("name") == expected["name"], f"Record {i}: expected name '{expected['name']}', got '{actual.get('name')}'"
        assert actual.get("total_asset_value") == expected["total_asset_value"], f"Record {i}: expected total_asset_value {expected['total_asset_value']}, got {actual.get('total_asset_value')}"
        assert actual.get("asset_count") == expected["asset_count"], f"Record {i}: expected asset_count {expected['asset_count']}, got {actual.get('asset_count')}"


def test_03_rust_project_and_required_sql():
    """Require an actual Cargo application containing the requested SQL operations."""
    cargo_toml = PROJECT_PATH / "Cargo.toml"
    source_dir = PROJECT_PATH / "src"
    assert PROJECT_PATH.is_dir(), "Missing Rust project at /home/user/audit_tool"
    assert cargo_toml.is_file(), "Missing Cargo.toml in /home/user/audit_tool"
    assert source_dir.is_dir(), "Missing src directory in the Rust project"

    rust_files = sorted(source_dir.rglob("*.rs"))
    assert rust_files, "The Cargo project contains no Rust source files"
    source = "\n".join(path.read_text(errors="replace") for path in rust_files).lower()

    assert re.search(r"drop\s+index\s+if\s+exists\s+idx_employee_assets", source, re.S), \
        "Rust source must issue DROP INDEX IF EXISTS idx_employee_assets"
    assert re.search(r"create\s+index(?:\s+if\s+not\s+exists)?\s+idx_assets_emp_val", source, re.S), \
        "Rust source must create idx_assets_emp_val"
    assert re.search(r"idx_assets_emp_val\s+on\s+assets\s*\(\s*employee_id\s*,\s*value\s+desc\s*\)", source, re.S), \
        "Rust source must define idx_assets_emp_val on (employee_id, value DESC)"
    assert re.search(r"with\s+recursive\b", source, re.S), \
        "Rust source must use a recursive CTE"
    assert re.search(r"\bsum\s*\(", source, re.S) and re.search(r"\bcount\s*\(", source, re.S), \
        "The recursive query must aggregate asset value and count"


def test_04_execute_application_on_changed_database():
    """Change the input, execute the Cargo application, and derive the expected report independently."""
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    max_employee = cur.execute("SELECT COALESCE(MAX(id), 0) FROM employees").fetchone()[0]
    max_asset = cur.execute("SELECT COALESCE(MAX(id), 0) FROM assets").fetchone()[0]
    child = max_employee + 101
    grandchild = max_employee + 102
    no_asset_child = max_employee + 103
    unrelated = max_employee + 104

    cur.execute("UPDATE assets SET value = value + (id % 17) * 13")
    cur.executemany(
        "INSERT INTO employees(id, name, manager_id) VALUES (?, ?, ?)",
        [
            (child, "Verifier Child", 5),
            (grandchild, "Verifier Grandchild", child),
            (no_asset_child, "Verifier No Assets", child),
            (unrelated, "Outside Hierarchy", None),
        ],
    )
    cur.executemany(
        "INSERT INTO assets(id, employee_id, asset_tag, value) VALUES (?, ?, ?, ?)",
        [
            (max_asset + 101, child, "DYNAMIC-CHILD", 7777),
            (max_asset + 102, grandchild, "DYNAMIC-GRANDCHILD", 111),
            (max_asset + 103, unrelated, "DYNAMIC-OUTSIDE", 999999),
        ],
    )

    employees = cur.execute("SELECT id, name, manager_id FROM employees").fetchall()
    assets = cur.execute("SELECT id, employee_id, asset_tag, value FROM assets").fetchall()

    children = {}
    names = {}
    for employee_id, name, manager_id in employees:
        names[employee_id] = name
        children.setdefault(manager_id, []).append(employee_id)

    reachable = []
    pending = [1]
    seen = set()
    while pending:
        employee_id = pending.pop(0)
        if employee_id in seen or employee_id not in names:
            continue
        seen.add(employee_id)
        reachable.append(employee_id)
        pending.extend(children.get(employee_id, []))

    totals = {employee_id: [0, 0] for employee_id in reachable}
    for _asset_id, employee_id, _tag, value in assets:
        if employee_id in totals:
            totals[employee_id][0] += value
            totals[employee_id][1] += 1

    expected = [
        {
            "employee_id": employee_id,
            "name": names[employee_id],
            "total_asset_value": totals[employee_id][0],
            "asset_count": totals[employee_id][1],
        }
        for employee_id in reachable
    ]
    expected.sort(key=lambda row: (-row["total_asset_value"], row["employee_id"]))

    employee_snapshot = list(employees)
    asset_snapshot = list(assets)

    cur.execute("DROP INDEX IF EXISTS idx_assets_emp_val")
    cur.execute("DROP INDEX IF EXISTS idx_employee_assets")
    cur.execute("CREATE INDEX idx_employee_assets ON assets(employee_id)")
    conn.commit()
    conn.close()

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    env = os.environ.copy()
    env["CARGO_NET_OFFLINE"] = "true"
    try:
        result = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT_PATH / "Cargo.toml")],
            cwd=str(PROJECT_PATH),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The Rust application timed out when executed")

    assert result.returncode == 0, "cargo run failed:\n" + result.stdout[-4000:]
    assert os.path.isfile(REPORT_PATH), "Running the Rust application did not create audit_report.json"

    with open(REPORT_PATH, "r") as report_file:
        try:
            actual = json.load(report_file)
        except json.JSONDecodeError as exc:
            pytest.fail(f"The newly generated report is invalid JSON: {exc}")

    assert actual == expected, "The executed application did not produce the derived recursive hierarchy report"

    conn = sqlite3.connect(DB_PATH)
    assert conn.execute("SELECT id, name, manager_id FROM employees").fetchall() == employee_snapshot, \
        "The application must not alter employee data"
    assert conn.execute("SELECT id, employee_id, asset_tag, value FROM assets").fetchall() == asset_snapshot, \
        "The application must not alter asset data"
    conn.close()

    assert_database_indexes()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
