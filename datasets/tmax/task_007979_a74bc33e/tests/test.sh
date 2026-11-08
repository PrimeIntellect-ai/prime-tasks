#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import sqlite3
import string
import subprocess
from collections import Counter
from datetime import datetime

SCRIPT = "/home/user/audit.sh"
DB = "/home/user/audit.db"
ORG = "/home/user/org_chart.json"
LOGS = "/home/user/access_logs.json"


def run_script(emp_id):
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    result = subprocess.run(["bash", SCRIPT, emp_id], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed for {emp_id} with error: {result.stderr}"


def read_output(emp_id):
    output_file = f"/home/user/flagged_{emp_id}.csv"
    assert os.path.exists(output_file), f"Output file {output_file} was not created."
    with open(output_file, newline="") as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, f"{output_file} is empty."
    assert rows[0] == ["user_id", "timestamp", "rolling_bytes"], f"Incorrect header in {output_file}."
    return rows[1:]


def test_original_and_dynamic_behavior():
    # Preserve the original fixed assertions.
    run_script("E01")
    actual_rows = read_output("E01")
    expected_rows = [
        ["E05", "2023-10-01T10:10:00Z", "6000"],
        ["E04", "2023-10-01T10:12:00Z", "6000"],
        ["E02", "2023-10-01T11:00:00Z", "6000"]
    ]
    assert actual_rows == expected_rows, f"Data rows in /home/user/flagged_E01.csv do not match expected output.\nExpected: {expected_rows}\nActual: {actual_rows}"

    run_script("E03")
    actual_rows = read_output("E03")
    expected_rows = [["E05", "2023-10-01T10:10:00Z", "6000"]]
    assert actual_rows == expected_rows, f"Data rows in /home/user/flagged_E03.csv do not match expected output.\nExpected: {expected_rows}\nActual: {actual_rows}"
    assert os.path.exists(DB), f"Database {DB} was not created."

    # The required implementation constructs must be present in the submitted script.
    with open(SCRIPT, encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"\bjq\b", source), "audit.sh does not use jq."
    assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.I | re.S), "audit.sh does not contain a recursive CTE."
    assert re.search(r"\bOVER\s*\(", source, re.I | re.S), "audit.sh does not contain a SQL window function."

    # Replace both extracts with unpredictable employee IDs and contents so a script
    # branching on the shipped E01/E03 examples cannot pass.
    token = ''.join(random.SystemRandom().choices(string.ascii_uppercase + string.digits, k=10))
    ids = {name: f"{name}{token}" for name in ("ROOT", "A", "A1", "B", "B1")}
    outsider = f"OUT{token}"
    org_doc = {
        "id": ids["ROOT"], "name": "root", "subordinates": [
            {"id": ids["A"], "name": "a", "subordinates": [
                {"id": ids["A1"], "name": "a1", "subordinates": []}
            ]},
            {"id": ids["B"], "name": "b", "subordinates": [
                {"id": ids["B1"], "name": "b1", "subordinates": []}
            ]}
        ]
    }
    logs_doc = [
        {"user_id": ids["A"], "timestamp": "2025-04-17T09:00:00Z", "action": "download", "bytes": 2600},
        {"user_id": ids["B"], "timestamp": "2025-04-17T09:02:00Z", "action": "upload", "bytes": 6001},
        {"user_id": outsider, "timestamp": "2025-04-17T09:03:00Z", "action": "download", "bytes": 9000},
        {"user_id": ids["A1"], "timestamp": "2025-04-17T09:04:00Z", "action": "download", "bytes": 3000},
        {"user_id": ids["A"], "timestamp": "2025-04-17T09:07:00Z", "action": "upload", "bytes": 2601},
        {"user_id": ids["A1"], "timestamp": "2025-04-17T09:10:00Z", "action": "download", "bytes": 2501},
        {"user_id": ids["B1"], "timestamp": "2025-04-17T09:11:00Z", "action": "blocked", "bytes": 99999},
        {"user_id": ids["B1"], "timestamp": "2025-04-17T09:12:00Z", "action": "download", "bytes": 100},
        {"user_id": ids["ROOT"], "timestamp": "2025-04-17T09:20:00Z", "action": "download", "bytes": 5001},
        {"user_id": ids["A"], "timestamp": "2025-04-17T09:30:00Z", "action": "download", "bytes": 100}
    ]
    with open(ORG, "w") as f:
        json.dump(org_doc, f)
    with open(LOGS, "w") as f:
        json.dump(logs_doc, f)
    if os.path.exists(DB):
        os.remove(DB)

    children = {
        ids["ROOT"]: [ids["A"], ids["B"]],
        ids["A"]: [ids["A1"]], ids["A1"]: [],
        ids["B"]: [ids["B1"]], ids["B1"]: []
    }

    def descendants(start):
        result, stack = set(), [start]
        while stack:
            current = stack.pop()
            if current in result:
                continue
            result.add(current)
            stack.extend(children.get(current, []))
        return result

    def epoch(value):
        return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())

    def expected_for(start):
        scope = descendants(start)
        allowed = [x for x in logs_doc if x["action"] != "blocked" and x["user_id"] in scope]
        result = []
        for row in allowed:
            now = epoch(row["timestamp"])
            rolling = sum(
                other["bytes"] for other in allowed
                if other["user_id"] == row["user_id"] and now - 900 <= epoch(other["timestamp"]) <= now
            )
            if rolling > 5000:
                result.append([row["user_id"], row["timestamp"], str(rolling)])
        return sorted(result, key=lambda x: (x[1], x[0]))

    for emp_id in (ids["ROOT"], ids["A"], ids["B"], ids["B1"]):
        output = f"/home/user/flagged_{emp_id}.csv"
        if os.path.exists(output):
            os.remove(output)
        run_script(emp_id)
        actual = read_output(emp_id)
        normalized = [[r[0], r[1], str(int(float(r[2])))] for r in actual]
        expected = expected_for(emp_id)
        assert normalized == expected, f"Wrong dynamic output for {emp_id}. Expected {expected}, got {actual}"

    # Verify that the requested relational artifact contains the imported hierarchy
    # and all and only the non-blocked logs from the replacement extracts.
    assert os.path.isfile(DB), f"Database {DB} was not created."
    con = sqlite3.connect(DB)
    try:
        tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert "org" in tables and "logs" in tables, f"Database tables missing; found {tables}"
        org_cols = {r[1] for r in con.execute("PRAGMA table_info(org)")}
        log_cols = {r[1] for r in con.execute("PRAGMA table_info(logs)")}
        assert {"employee_id", "manager_id"} <= org_cols, f"Incorrect org schema: {org_cols}"
        assert {"user_id", "timestamp", "bytes"} <= log_cols, f"Incorrect logs schema: {log_cols}"

        actual_org = set(con.execute("SELECT employee_id, manager_id FROM org"))
        expected_org = {
            (ids["ROOT"], None), (ids["A"], ids["ROOT"]),
            (ids["A1"], ids["A"]), (ids["B"], ids["ROOT"]),
            (ids["B1"], ids["B"])
        }
        actual_org = {(e, None if m in (None, "") else m) for e, m in actual_org}
        assert actual_org == expected_org, f"Incorrect flattened hierarchy: {actual_org}"

        actual_logs = Counter((u, ts, int(b)) for u, ts, b in con.execute("SELECT user_id, timestamp, bytes FROM logs"))
        expected_logs = Counter((x["user_id"], x["timestamp"], x["bytes"]) for x in logs_doc if x["action"] != "blocked")
        assert actual_logs == expected_logs, "logs table is not an exact import of the jq-filtered non-blocked records."
    finally:
        con.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
