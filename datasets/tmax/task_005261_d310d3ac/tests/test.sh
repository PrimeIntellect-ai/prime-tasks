#!/bin/bash
mkdir -p /logs/verifier

SQLITE_BIN="$(command -v sqlite3 2>/dev/null)"
REAL_SQLITE="/tmp/verifier_sqlite3_real.$$"
SQLITE_LOG="/tmp/verifier_sqlite_calls.log"
WRAPPER_INSTALLED=0

cleanup() {
    if [ "$WRAPPER_INSTALLED" -eq 1 ] && [ -e "$REAL_SQLITE" ]; then
        rm -f "$SQLITE_BIN"
        mv "$REAL_SQLITE" "$SQLITE_BIN"
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess

import pytest

SCRIPT_PATH = "/home/user/generate_report.sh"
REPORT_PATH = "/home/user/report.json"
DB_PATH = "/home/user/graph.db"
SQLITE_LOG = "/tmp/verifier_sqlite_calls.log"

EXPECTED_ORIGINAL = [
    {"id": 1, "name": "Core", "type": "System", "total_cost": 310, "cost_rank": 1},
    {"id": 2, "name": "Module A", "type": "Module", "total_cost": 100, "cost_rank": 2},
    {"id": 3, "name": "Module B", "type": "Module", "total_cost": 110, "cost_rank": 1},
    {"id": 4, "name": "Sub A1", "type": "Submodule", "total_cost": 20, "cost_rank": 3},
    {"id": 5, "name": "Sub A2", "type": "Submodule", "total_cost": 30, "cost_rank": 2},
    {"id": 6, "name": "Sub B1", "type": "Submodule", "total_cost": 40, "cost_rank": 1},
    {"id": 7, "name": "Sub B2", "type": "Submodule", "total_cost": 10, "cost_rank": 4},
]

DYNAMIC_ROWS = [
    (101, None, "Alpha Root", 17, "System"),
    (205, 101, "Beta Branch", 8, "Module"),
    (309, 205, "Gamma Node", 6, "Module"),
    (412, 101, "Delta Node", 3, "Module"),
    (550, None, "Omega Root", 29, "System"),
    (777, 550, "Epsilon Branch", 11, "Module"),
    (888, 777, "Zeta Leaf", 2, "Leaf"),
]

KEYS = {"id", "name", "type", "total_cost", "cost_rank"}


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, "r", errors="replace") as f:
        first_line = f.readline()
    assert re.match(r"^#!.*(?:/|\b)bash(?:\s|$)", first_line), "generate_report.sh must be a Bash script"


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    with open(SQLITE_LOG, "w"):
        pass
    result = subprocess.run(
        [SCRIPT_PATH], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f"generate_report.sh failed with exit code {result.returncode}: {result.stderr}"
    )


def test_report_exists():
    run_script()
    assert os.path.isfile(REPORT_PATH), f"Report missing at {REPORT_PATH}"


def load_and_check_report(expected):
    try:
        with open(REPORT_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "Report JSON must be an array of objects."
    assert len(data) == len(expected), f"Expected {len(expected)} items, but found {len(data)}."

    for i, (actual, wanted) in enumerate(zip(data, expected)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        for key in ["id", "name", "type", "total_cost", "cost_rank"]:
            assert key in actual, f"Item at index {i} is missing key '{key}'"
            assert actual[key] == wanted[key], (
                f"Mismatch at index {i} for key '{key}': expected {wanted[key]}, got {actual[key]}"
            )
        assert set(actual) == KEYS, f"Item at index {i} does not have the exact required keys"


def assert_executed_required_sql():
    with open(SQLITE_LOG, "r", errors="replace") as f:
        trace = f.read()
    invocations = [part for part in trace.split("=== SQLITE INVOCATION ===") if part.strip()]
    assert invocations, "The script did not execute sqlite3"

    recursive = re.compile(r"\bWITH\s+RECURSIVE\b", re.IGNORECASE | re.DOTALL)
    window_rank = re.compile(
        r"\b(?:RANK|DENSE_RANK|ROW_NUMBER)\s*\(\s*\)\s*OVER\s*\(",
        re.IGNORECASE | re.DOTALL,
    )
    assert any(recursive.search(call) and window_rank.search(call) for call in invocations), (
        "A sqlite3 query executed by the script must contain both a recursive CTE and a ranking window function"
    )


def make_dynamic_database():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    con = sqlite3.connect(DB_PATH)
    try:
        con.execute("""
            CREATE TABLE components (
                id INTEGER PRIMARY KEY,
                parent_id INTEGER,
                name TEXT,
                base_cost INTEGER,
                type TEXT
            )
        """)
        con.executemany("INSERT INTO components VALUES (?, ?, ?, ?, ?)", DYNAMIC_ROWS)
        con.commit()
    finally:
        con.close()


def derive_expected(rows):
    by_id = {row[0]: row for row in rows}
    children = {row[0]: [] for row in rows}
    for row in rows:
        if row[1] is not None:
            children[row[1]].append(row[0])

    def total(node_id):
        return by_id[node_id][3] + sum(total(child) for child in children[node_id])

    totals = {node_id: total(node_id) for node_id in by_id}
    ranks = {}
    types = {row[4] for row in rows}
    for component_type in types:
        ids = [row[0] for row in rows if row[4] == component_type]
        ordered_totals = sorted((totals[node_id] for node_id in ids), reverse=True)
        for node_id in ids:
            ranks[node_id] = ordered_totals.index(totals[node_id]) + 1

    return [
        {
            "id": row[0], "name": row[2], "type": row[4],
            "total_cost": totals[row[0]], "cost_rank": ranks[row[0]],
        }
        for row in sorted(rows, key=lambda item: item[0])
    ]


def test_report_content():
    # Preserve the original exact-content assertion, but only after executing the artifact.
    load_and_check_report(EXPECTED_ORIGINAL)
    assert_executed_required_sql()

    backup = "/tmp/verifier_graph_backup.db"
    shutil.copy2(DB_PATH, backup)
    try:
        make_dynamic_database()
        run_script()
        assert os.path.isfile(REPORT_PATH), f"Report missing at {REPORT_PATH}"
        load_and_check_report(derive_expected(DYNAMIC_ROWS))
        assert_executed_required_sql()
    finally:
        shutil.copy2(backup, DB_PATH)
        os.remove(backup)
TEST_EOF

STATUS=1
if [ -n "$SQLITE_BIN" ] && [ -x "$SQLITE_BIN" ]; then
    mv "$SQLITE_BIN" "$REAL_SQLITE"
    WRAPPER_INSTALLED=1
    cat > "$SQLITE_BIN" <<WRAPPER_EOF
#!/bin/bash
stdin_file=\$(mktemp)
cat > "\$stdin_file"
{
    echo '=== SQLITE INVOCATION ==='
    printf 'ARG: %s\n' "\$@"
    echo '--- STDIN ---'
    cat "\$stdin_file"
    echo
} >> "$SQLITE_LOG"
"$REAL_SQLITE" "\$@" < "\$stdin_file"
rc=\$?
rm -f "\$stdin_file"
exit \$rc
WRAPPER_EOF
    chmod 755 "$SQLITE_BIN"

    if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        STATUS=0
    fi
fi

cleanup
trap - EXIT

if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
