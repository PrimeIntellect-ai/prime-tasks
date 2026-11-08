#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import sqlite3
import stat
import subprocess
from collections import defaultdict

import pytest

SCRIPT_PATH = "/home/user/generate_report.sh"
REPORT_PATH = "/home/user/report.csv"
DB_PATH = "/home/user/app.db"

EXPECTED_ACCOUNTS = [
    (1, None),
    (2, 1),
    (3, 2),
    (4, None),
    (5, 4),
    (6, 4),
]

EXPECTED_LOGS = [
    (1, 1, '{"query_time_ms": 10}', '2023-01-01 10:00:00'),
    (2, 1, '{"query_time_ms": 20}', '2023-01-01 10:01:00'),
    (3, 2, '{"query_time_ms": 60}', '2023-01-01 10:00:00'),
    (4, 2, '{"query_time_ms": 60}', '2023-01-01 10:01:00'),
    (5, 3, '{"query_time_ms": 100}', '2023-01-01 10:00:00'),
    (6, 3, '{"query_time_ms": 15}', '2023-01-01 10:01:00'),
    (7, 4, '{"query_time_ms": 200}', '2023-01-01 10:00:00'),
    (8, 4, '{"query_time_ms": 50}', '2023-01-01 10:01:00'),
    (9, 5, '{"query_time_ms": 30}', '2023-01-01 10:00:00'),
    (10, 5, '{"query_time_ms": 10}', '2023-01-01 10:01:00'),
    (11, 6, '{"query_time_ms": 80}', '2023-01-01 10:00:00'),
    (12, 6, '{"query_time_ms": 25}', '2023-01-01 10:01:00'),
]

EXPECTED_TABLE_INFO = {
    "accounts": [
        (0, "account_id", "INTEGER", 0, None, 1),
        (1, "parent_account_id", "INTEGER", 0, None, 0),
    ],
    "logs": [
        (0, "log_id", "INTEGER", 0, None, 1),
        (1, "account_id", "INTEGER", 0, None, 0),
        (2, "data", "TEXT", 0, None, 0),
        (3, "created_at", "DATETIME", 0, None, 0),
    ],
}


def assert_original_database():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} is missing."
    assert not os.path.islink(DB_PATH), f"Database {DB_PATH} must remain the original regular file."

    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    try:
        assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        objects = conn.execute(
            "SELECT type, name FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        ).fetchall()
        assert objects == [("table", "accounts"), ("table", "logs")], (
            f"Database objects were modified: {objects}"
        )
        for table, expected_info in EXPECTED_TABLE_INFO.items():
            actual_info = conn.execute(f"PRAGMA table_info({table})").fetchall()
            assert actual_info == expected_info, f"Schema for {table} was modified."

        accounts = conn.execute(
            "SELECT account_id, parent_account_id FROM accounts ORDER BY account_id"
        ).fetchall()
        logs = conn.execute(
            "SELECT log_id, account_id, data, created_at FROM logs ORDER BY log_id"
        ).fetchall()
        assert accounts == EXPECTED_ACCOUNTS, "The accounts table was modified."
        assert logs == EXPECTED_LOGS, "The logs table was modified."
    finally:
        conn.close()


def database_hash():
    digest = hashlib.sha256()
    with open(DB_PATH, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert_original_database()
    before_hash = database_hash()

    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable by the owner."
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line in ("#!/bin/bash", "#!/usr/bin/bash", "#!/usr/bin/env bash"), (
        "generate_report.sh must be an executable Bash script with a Bash shebang."
    )

    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"generate_report.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert_original_database()
    assert database_hash() == before_hash, "generate_report.sh modified the original database file."


def test_script_exists_and_executable():
    """Test that the bash script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable by the owner."


def test_report_exists():
    """Test that the report CSV file was generated."""
    assert os.path.isfile(REPORT_PATH), f"Report {REPORT_PATH} does not exist."


def get_expected_report():
    """Helper to recompute the expected report directly from the database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT account_id, parent_account_id FROM accounts")
    accounts = cursor.fetchall()
    parent_map = {acc[0]: acc[1] for acc in accounts}

    def get_root(acc_id):
        curr = acc_id
        while parent_map.get(curr) is not None:
            curr = parent_map[curr]
        return curr

    roots = {acc[0]: get_root(acc[0]) for acc in accounts}

    cursor.execute("SELECT account_id, data, created_at FROM logs")
    logs = cursor.fetchall()
    conn.close()

    account_logs = defaultdict(list)
    for acc_id, data_str, created_at in logs:
        try:
            data = json.loads(data_str)
            qt = data.get("query_time_ms", 0)
        except Exception:
            qt = 0
        account_logs[acc_id].append((created_at, qt))

    results = []
    for acc_id, log_entries in account_logs.items():
        log_entries.sort(key=lambda x: x[0])
        max_rolling = 0
        for i in range(len(log_entries)):
            if i == 0:
                rolling = log_entries[i][1]
            else:
                rolling = log_entries[i][1] + log_entries[i - 1][1]
            if rolling > max_rolling:
                max_rolling = rolling

        if max_rolling > 100:
            results.append((acc_id, roots[acc_id], max_rolling))

    results.sort(key=lambda x: (-x[2], x[0]))
    results = results[:5]
    return [f"{r[0]},{r[1]},{r[2]}" for r in results]


def test_report_content():
    """Test that the report CSV contains exactly the expected data."""
    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()

    expected_lines = get_expected_report()
    actual_lines = [line.strip() for line in content.split("\n") if line.strip()]

    assert actual_lines == expected_lines, (
        f"Report content is incorrect.\n"
        f"Expected:\n{expected_lines}\n\n"
        f"Got:\n{actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
