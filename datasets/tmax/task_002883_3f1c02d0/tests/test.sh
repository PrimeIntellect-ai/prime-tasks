#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import sqlite3

def test_audit_report_exists_and_valid():
    report_path = '/home/user/audit_report.json'
    assert os.path.exists(report_path), f"Audit report missing at {report_path}"

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "Audit report is not valid JSON"

    assert "paths" in data, "JSON missing 'paths' key"
    paths = data["paths"]
    assert isinstance(paths, list), "'paths' should be a list"
    assert len(paths) == 5, f"Expected exactly 5 paths, found {len(paths)}"

    expected_paths = [
        {"route": ["C-100", "M", "C-999"], "total_amount": 1000.0},
        {"route": ["C-100", "X", "Y", "Z", "C-999"], "total_amount": 800.0},
        {"route": ["C-100", "P", "Q", "C-999"], "total_amount": 450.0},
        {"route": ["C-100", "A", "B", "C-999"], "total_amount": 300.0},
        {"route": ["C-100", "S", "C-999"], "total_amount": 140.0}
    ]

    for i, expected in enumerate(expected_paths):
        actual = paths[i]
        assert "route" in actual, f"Path {i} missing 'route'"
        assert "total_amount" in actual, f"Path {i} missing 'total_amount'"
        assert actual["route"] == expected["route"], f"Expected route {expected['route']} at index {i}, got {actual['route']}"
        assert actual["total_amount"] == expected["total_amount"], f"Expected total_amount {expected['total_amount']} at index {i}, got {actual['total_amount']}"

def test_database_indices_created():
    db_path = '/home/user/financial_logs.db'
    assert os.path.exists(db_path), f"Database file missing at {db_path}"

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='transfers'")
    indices = c.fetchall()

    user_indices = [idx[0] for idx in indices if not idx[0].startswith('sqlite_autoindex')]
    assert len(user_indices) > 0, "No user-created indices found on the 'transfers' table"

    leading_columns = set()
    for index_name in user_indices:
        c.execute("PRAGMA index_info(%s)" % json.dumps(index_name))
        columns = sorted(c.fetchall(), key=lambda row: row[0])
        if columns:
            leading_columns.add(columns[0][2])
    conn.close()

    assert 'sender' in leading_columns, "No user-created index optimized for lookups by sender"
    assert 'receiver' in leading_columns, "No user-created index optimized for lookups by receiver"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
