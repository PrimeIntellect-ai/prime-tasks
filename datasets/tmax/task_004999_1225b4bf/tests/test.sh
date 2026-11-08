#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/analyze_audit.sh"
REPORT_PATH = "/home/user/compromise_report.csv"
DB_PATH = "/home/user/audit.db"


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/tmp",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(REPORT_PATH), f"Script did not create {REPORT_PATH}."


def expected_report_from_db():
    connection = sqlite3.connect(DB_PATH)
    try:
        entities = {
            row[0]: {"name": row[1], "type": row[2], "status": row[3]}
            for row in connection.execute("SELECT id, name, type, status FROM Entities")
        }
        adjacency = {}
        for source_id, target_id in connection.execute(
            "SELECT source_id, target_id FROM AccessGrants WHERE status = 'ACTIVE'"
        ):
            adjacency.setdefault(source_id, []).append(target_id)
    finally:
        connection.close()

    sensitive_types = {"DATA_LAKE", "FINANCE_DB"}
    rows = []

    def walk(source_name, current_id, hops, visited):
        current = entities.get(current_id)
        if current is None:
            return
        if current["type"] in sensitive_types:
            rows.append((source_name, current["name"], hops))
            return
        for target_id in adjacency.get(current_id, []):
            if target_id not in visited:
                walk(source_name, target_id, hops + 1, visited | {target_id})

    for entity_id, entity in entities.items():
        if entity["type"] == "USER" and entity["status"] == "REVOKED":
            walk(entity["name"], entity_id, 0, {entity_id})

    rows.sort(key=lambda row: (row[2], row[0], row[1]))
    return [["Source_User", "Target_Entity", "Hops"]] + [
        [source, target, str(hops)] for source, target, hops in rows
    ]


def read_report():
    with open(REPORT_PATH, newline="") as report_file:
        return list(csv.reader(report_file))


def test_script_exists_and_executable():
    """Check if the bash script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_uses_one_sqlite_recursive_cte():
    with open(SCRIPT_PATH, "r", errors="replace") as script_file:
        source = script_file.read()

    non_comment_source = "\n".join(
        line for line in source.splitlines()
        if not line.lstrip().startswith("#") and not line.lstrip().startswith("--")
    )
    sqlite_commands = re.findall(
        r"(?mi)^[ \t]*(?:(?:/[^\s]+/)?sqlite3)\b", non_comment_source
    )
    assert len(sqlite_commands) == 1, (
        "The script must invoke sqlite3 exactly once for its single SQLite query."
    )
    assert len(re.findall(r"\bWITH\s+RECURSIVE\b", non_comment_source, re.I)) == 1, (
        "The SQLite query must contain a recursive CTE introduced by WITH RECURSIVE."
    )


def test_report_content():
    """Execute the script and check that the generated report matches the original expected output."""
    run_script()

    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "Source_User,Target_Entity,Hops",
        "alice_admin,CustomerData,2",
        "charlie_ops,CustomerData,2",
        "charlie_ops,TempData,2",
        "alice_admin,LedgerMain,3"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Report content does not match expected output.\n"
        f"Expected:\n{expected_lines}\n"
        f"Actual:\n{actual_lines}"
    )


def test_script_recomputes_report_from_changed_database():
    with tempfile.TemporaryDirectory() as backup_dir:
        db_backup = os.path.join(backup_dir, "audit.db")
        shutil.copy2(DB_PATH, db_backup)
        report_backup = None
        if os.path.exists(REPORT_PATH):
            report_backup = os.path.join(backup_dir, "compromise_report.csv")
            shutil.copy2(REPORT_PATH, report_backup)

        try:
            connection = sqlite3.connect(DB_PATH)
            try:
                next_id = connection.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM Entities").fetchone()[0]
                dana_id = next_id
                bridge_id = next_id + 1
                vault_id = next_id + 2
                connection.executemany(
                    "INSERT INTO Entities(id, name, type, status) VALUES (?, ?, ?, ?)",
                    [
                        (dana_id, "dana_qa", "USER", "REVOKED"),
                        (bridge_id, "audit_bridge", "GROUP", "ACTIVE"),
                        (vault_id, "ArchiveVault", "FINANCE_DB", "ACTIVE"),
                    ],
                )
                connection.executemany(
                    "INSERT INTO AccessGrants(source_id, target_id, status) VALUES (?, ?, ?)",
                    [
                        (dana_id, bridge_id, "ACTIVE"),
                        (bridge_id, vault_id, "ACTIVE"),
                        (1, vault_id, "ACTIVE"),
                        (2, vault_id, "ACTIVE"),
                        (dana_id, 10, "INACTIVE"),
                        (9, vault_id, "ACTIVE"),
                    ],
                )
                connection.commit()
            finally:
                connection.close()

            expected = expected_report_from_db()
            run_script()
            actual = read_report()
            assert actual == expected, (
                "The script did not recompute the recursive traversal from the modified audit.db, "
                "or it failed to stop traversal at a sensitive entity.\n"
                f"Expected: {expected}\nActual: {actual}"
            )
        finally:
            shutil.copy2(db_backup, DB_PATH)
            if report_backup is not None:
                shutil.copy2(report_backup, REPORT_PATH)
            elif os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
