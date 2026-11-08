#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

DB_PATH = "/home/user/backup_metadata.db"
GENERATE_SCRIPT = "/home/user/generate_report.sh"
OPTIMIZE_SCRIPT = "/home/user/optimize.sh"
REPORT_PATH = "/home/user/final_report.csv"

EXPECTED_CSV = [
    "cache-master,ROOT,210",
    "cache-node1,cache-master,190",
    "db-main,ROOT,1060",
    "db-replica1,db-main,955",
    "db-replica2,db-main,960"
]


def test_scripts_exist_and_executable():
    for script in [GENERATE_SCRIPT, OPTIMIZE_SCRIPT]:
        assert os.path.exists(script), f"Script missing at {script}"
        assert os.path.isfile(script), f"{script} is not a file"
        st = os.stat(script)
        assert bool(st.st_mode & stat.S_IXUSR), f"{script} is not executable"


def test_generate_report_correctness():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run([GENERATE_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"{GENERATE_SCRIPT} failed to execute properly. Stderr: {result.stderr}"
    assert os.path.exists(REPORT_PATH), f"{REPORT_PATH} was not created by the script"

    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(EXPECTED_CSV), f"Expected {len(EXPECTED_CSV)} rows in CSV, got {len(lines)}"
    for i, (actual, expected) in enumerate(zip(lines, EXPECTED_CSV)):
        assert actual == expected, f"Row {i+1} mismatch: expected '{expected}', got '{actual}'"


def test_generate_script_contains_window_query():
    with open(GENERATE_SCRIPT, "r", errors="replace") as f:
        source = f.read()
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    source = re.sub(r"--[^\n]*", " ", source)
    source = re.sub(r"(?m)^\s*#[^\n]*", " ", source)
    assert re.search(r"\bOVER\s*\(", source, flags=re.I), \
        "generate_report.sh must execute a SQL window function using OVER (...)"
    assert re.search(r"\b(ROW_NUMBER|RANK|DENSE_RANK|FIRST_VALUE|LAST_VALUE|NTH_VALUE|MAX|MIN)\s*\([^)]*\)\s*OVER\s*\(", source, flags=re.I | re.S), \
        "No suitable SQL window function was found in generate_report.sh"


def test_generate_report_uses_current_database_data():
    fd, saved_db = tempfile.mkstemp(prefix="backup_metadata_saved_", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, saved_db)

    token = secrets.token_hex(6)
    hostnames = [
        f"alpha-{token}",
        f"bravo-{token}",
        f"charlie-{token}",
        f"delta-{token}",
        f"echo-{token}",
        f"foxtrot-{token}",
        f"golf-{token}",
    ]
    parents = [None, 1, 1, 2, None, 5, 6]
    expected = []

    try:
        for suffix in ("-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        os.remove(DB_PATH)

        conn = sqlite3.connect(DB_PATH)
        conn.executescript("""
            CREATE TABLE servers (
                id INTEGER PRIMARY KEY,
                hostname TEXT NOT NULL,
                parent_id INTEGER,
                FOREIGN KEY(parent_id) REFERENCES servers(id)
            );
            CREATE TABLE backups (
                id INTEGER PRIMARY KEY,
                server_id INTEGER NOT NULL,
                timestamp DATETIME NOT NULL,
                size_mb INTEGER NOT NULL,
                status TEXT NOT NULL,
                FOREIGN KEY(server_id) REFERENCES servers(id)
            );
        """)

        for server_id, (hostname, parent_id) in enumerate(zip(hostnames, parents), 1):
            conn.execute(
                "INSERT INTO servers(id, hostname, parent_id) VALUES (?, ?, ?)",
                (server_id, hostname, parent_id),
            )

        backup_id = 1
        for server_id in range(1, len(hostnames) + 1):
            old_size = 1000 + secrets.randbelow(5000)
            latest_size = 7000 + secrets.randbelow(5000)
            rows = [
                ("2041-01-01 08:00:00", old_size, "SUCCESS"),
                ("2041-01-05 08:00:00", latest_size + 9000, "FAILED"),
                ("2041-01-03 08:00:00", latest_size, "SUCCESS"),
            ]
            if server_id % 2 == 0:
                rows.append(("2041-01-02 08:00:00", old_size + 1, "SUCCESS"))
            for timestamp, size_mb, status_value in rows:
                conn.execute(
                    "INSERT INTO backups(id, server_id, timestamp, size_mb, status) VALUES (?, ?, ?, ?, ?)",
                    (backup_id, server_id, timestamp, size_mb, status_value),
                )
                backup_id += 1

            parent_hostname = "ROOT" if parents[server_id - 1] is None else hostnames[parents[server_id - 1] - 1]
            expected.append((hostnames[server_id - 1], parent_hostname, str(latest_size)))

        conn.commit()
        conn.close()
        expected.sort(key=lambda row: row[0])

        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        result = subprocess.run([GENERATE_SCRIPT], capture_output=True, text=True)
        assert result.returncode == 0, f"{GENERATE_SCRIPT} failed on changed database data. Stderr: {result.stderr}"
        assert os.path.exists(REPORT_PATH), f"{REPORT_PATH} was not created on changed database data"

        with open(REPORT_PATH, newline="") as f:
            actual = list(csv.reader(f))

        assert all(len(row) == 3 for row in actual), "Every report row must contain exactly three columns"
        assert actual == [list(row) for row in expected], \
            "Report does not reflect the current hierarchy and latest successful backups in the database"
    finally:
        for suffix in ("-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        os.replace(saved_db, DB_PATH)


def test_optimize_script_creates_index():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_backups_latest';")
    index_exists = cursor.fetchone() is not None
    if index_exists:
        cursor.execute("DROP INDEX idx_backups_latest;")
        conn.commit()
    conn.close()

    result = subprocess.run([OPTIMIZE_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"{OPTIMIZE_SCRIPT} failed to execute properly. Stderr: {result.stderr}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_backups_latest';")
    assert cursor.fetchone() is not None, "Index 'idx_backups_latest' was not created by optimize.sh"

    cursor.execute("SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_backups_latest';")
    tbl_name = cursor.fetchone()[0]
    assert tbl_name == 'backups', f"Index 'idx_backups_latest' is on table '{tbl_name}', expected 'backups'"

    cursor.execute("PRAGMA index_xinfo('idx_backups_latest')")
    key_columns = [row for row in cursor.fetchall() if row[5] == 1]
    assert [row[2] for row in key_columns] == ["server_id", "status", "timestamp"], \
        "idx_backups_latest must index server_id, status, and timestamp in that order"
    assert [row[3] for row in key_columns] == [0, 0, 1], \
        "idx_backups_latest must use ASC server_id, ASC status, and DESC timestamp ordering"
    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
