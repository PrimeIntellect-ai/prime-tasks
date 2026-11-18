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
import stat
import subprocess
import tempfile

REPORT_PATH = "/home/user/report.txt"
DB_PATH = "/home/user/backups.db"
SOURCE_PATH = "/home/user/analyze_backups.cpp"
EXECUTABLE_PATH = "/home/user/analyze_backups"


def get_expected_values():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("SELECT metadata FROM backup_events")
    total_size = 0
    for row in c.fetchall():
        meta = json.loads(row[0])
        if meta.get("status") == "archived":
            total_size += meta.get("size_bytes", 0)

    c.execute("SELECT id, parent_id FROM backup_events")
    edges = c.fetchall()
    children_map = {}
    for node_id, parent_id in edges:
        if parent_id is not None:
            children_map.setdefault(parent_id, []).append(node_id)

    def get_max_depth(node_id):
        if node_id not in children_map:
            return 0
        return 1 + max(get_max_depth(child) for child in children_map[node_id])

    c.execute("SELECT id FROM backup_events WHERE type='full'")
    full_backups = [row[0] for row in c.fetchall()]
    max_chain_length = 0
    if full_backups:
        max_chain_length = max(get_max_depth(fb) for fb in full_backups)

    c.execute('''
        SELECT dataset, id
        FROM backup_events
        WHERE type='full'
        ORDER BY timestamp DESC
    ''')
    latest_full = {}
    for dataset, backup_id in c.fetchall():
        if dataset not in latest_full:
            latest_full[dataset] = backup_id

    conn.close()
    return total_size, max_chain_length, latest_full


def expected_report():
    total_size, max_chain, latest_full = get_expected_values()
    lines = [
        f"Total Archived Size: {total_size}",
        f"Max Restoration Chain Length: {max_chain}",
        "Latest Full Backups:"
    ]
    for dataset in sorted(latest_full.keys()):
        lines.append(f"{dataset}: {latest_full[dataset]}")
    return "\n".join(lines).strip()


def assert_report_content(expected):
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        actual = f.read().strip()
    assert actual == expected, (
        "Report content does not match expected output.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."


def test_report_content():
    assert_report_content(expected_report())


def create_changed_database():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    token = secrets.token_hex(4)
    base_id = secrets.randbelow(500000) + 100000
    base_time = secrets.randbelow(500000) + 10000
    sizes = [secrets.randbelow(9000) + 101 for _ in range(12)]
    alpha = f"alpha_{token}"
    beta = f"beta_{token}"
    zeta = f"zeta_{token}"

    rows = [
        (base_id + 1, alpha, base_time + 10, "full", None,
         json.dumps({"status": "archived", "size_bytes": sizes[0]})),
        (base_id + 2, alpha, base_time + 20, "incremental", base_id + 1,
         json.dumps({"status": "archived", "size_bytes": sizes[1]})),
        (base_id + 3, alpha, base_time + 30, "incremental", base_id + 2,
         json.dumps({"status": "active", "size_bytes": sizes[2]})),
        (base_id + 4, alpha, base_time + 100, "full", None,
         json.dumps({"status": "active", "size_bytes": sizes[3]})),
        (base_id + 5, alpha, base_time + 110, "incremental", base_id + 4,
         json.dumps({"status": "archived", "size_bytes": sizes[4]})),
        (base_id + 10, beta, base_time + 40, "full", None,
         json.dumps({"status": "archived", "size_bytes": sizes[5]})),
        (base_id + 11, beta, base_time + 50, "incremental", base_id + 10,
         json.dumps({"status": "failed", "size_bytes": sizes[6]})),
        (base_id + 12, beta, base_time + 60, "incremental", base_id + 11,
         json.dumps({"status": "archived", "size_bytes": sizes[7]})),
        (base_id + 13, beta, base_time + 70, "incremental", base_id + 12,
         json.dumps({"status": "active", "size_bytes": sizes[8]})),
        (base_id + 14, beta, base_time + 80, "incremental", base_id + 13,
         json.dumps({"status": "archived", "size_bytes": sizes[9]})),
        (base_id + 15, beta, base_time + 65, "incremental", base_id + 12,
         json.dumps({"status": "archived", "size_bytes": sizes[10]})),
        (base_id + 20, zeta, base_time + 200, "full", None,
         json.dumps({"status": "active", "size_bytes": sizes[11]})),
    ]

    conn = sqlite3.connect(DB_PATH)
    conn.execute('''
        CREATE TABLE backup_events (
            id INTEGER PRIMARY KEY,
            dataset TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            type TEXT NOT NULL,
            parent_id INTEGER,
            metadata TEXT
        )
    ''')
    conn.executemany("INSERT INTO backup_events VALUES (?, ?, ?, ?, ?, ?)", rows)
    conn.commit()
    conn.close()


def run_program():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    subprocess.run([EXECUTABLE_PATH], check=True, timeout=15)
    assert os.path.isfile(REPORT_PATH), "The executable did not generate report.txt"


def test_source_builds_runs_and_handles_changed_database():
    assert os.path.exists(SOURCE_PATH), f"Missing required source file {SOURCE_PATH}"
    source_stat = os.lstat(SOURCE_PATH)
    assert stat.S_ISREG(source_stat.st_mode) and not stat.S_ISLNK(source_stat.st_mode), \
        "analyze_backups.cpp must be a regular source file"

    with open(SOURCE_PATH, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"\b(?:ROW_NUMBER|RANK|DENSE_RANK)\s*\(", source, re.IGNORECASE), \
        "The C++ program must use a SQL window function to select latest full backups"
    assert re.search(r"\bjson_extract\s*\(", source, re.IGNORECASE), \
        "The C++ program must aggregate metadata using SQLite JSON functions"
    assert re.search(r"\bparent_id\b", source, re.IGNORECASE), \
        "The C++ program must read parent_id values for the dependency graph"

    original_expected = expected_report()
    saved_report = None
    if os.path.isfile(REPORT_PATH):
        with open(REPORT_PATH, "rb") as f:
            saved_report = f.read()

    with tempfile.TemporaryDirectory() as td:
        db_backup = os.path.join(td, "backups.db")
        shutil.copy2(DB_PATH, db_backup)
        try:
            if os.path.exists(EXECUTABLE_PATH):
                os.remove(EXECUTABLE_PATH)
            subprocess.run([
                "g++", "-std=c++17", SOURCE_PATH, "-lsqlite3", "-o", EXECUTABLE_PATH
            ], check=True, timeout=30)
            assert os.path.isfile(EXECUTABLE_PATH) and os.access(EXECUTABLE_PATH, os.X_OK)
            with open(EXECUTABLE_PATH, "rb") as f:
                assert f.read(4) == b"\x7fELF", "Compiled artifact is not an ELF executable"

            run_program()
            assert_report_content(original_expected)

            shutil.copy2(db_backup, DB_PATH)
            create_changed_database()
            changed_expected = expected_report()
            run_program()
            assert_report_content(changed_expected)
        finally:
            shutil.copy2(db_backup, DB_PATH)
            if saved_report is None:
                if os.path.exists(REPORT_PATH):
                    os.remove(REPORT_PATH)
            else:
                with open(REPORT_PATH, "wb") as f:
                    f.write(saved_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
