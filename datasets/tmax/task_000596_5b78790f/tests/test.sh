#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
from decimal import Decimal, ROUND_HALF_UP

import pytest

DB_PATH = "/home/user/data.db"
PROJECT_PATH = "/home/user/etl"
MANIFEST_PATH = os.path.join(PROJECT_PATH, "Cargo.toml")


def test_rolling_stats_table_exists():
    assert os.path.isfile(DB_PATH), f"The database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='rolling_stats';")
    assert cursor.fetchone() is not None, "Table 'rolling_stats' was not created in the database."
    conn.close()


def test_rolling_stats_data():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT user_id, username, event_date, rolling_avg FROM rolling_stats ORDER BY user_id ASC, event_date ASC;")
        rows = cursor.fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query 'rolling_stats': {e}")
    finally:
        conn.close()

    expected_data = [
        (1, 'alice', '2023-01-01', 10.0),
        (1, 'alice', '2023-01-03', 15.0),
        (1, 'alice', '2023-01-05', 20.0),
        (1, 'alice', '2023-01-07', 30.0),
        (2, 'bob', '2023-01-02', 15.0),
        (2, 'bob', '2023-01-04', 20.0),
        (2, 'bob', '2023-01-06', 15.0)
    ]

    assert len(rows) == len(expected_data), f"Expected {len(expected_data)} rows in rolling_stats, found {len(rows)}."

    for i, (actual, expected) in enumerate(zip(rows, expected_data)):
        assert actual[0] == expected[0], f"Row {i+1}: expected user_id {expected[0]}, got {actual[0]}"
        assert actual[1] == expected[1], f"Row {i+1}: expected username {expected[1]}, got {actual[1]}"
        assert actual[2] == expected[2], f"Row {i+1}: expected event_date {expected[2]}, got {actual[2]}"
        assert abs(actual[3] - expected[3]) < 1e-5, f"Row {i+1}: expected rolling_avg {expected[3]}, got {actual[3]}"


def test_original_tables_unmodified():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM users;")
    user_count = cursor.fetchone()[0]
    assert user_count == 2, f"Expected 2 users to remain, found {user_count}"

    cursor.execute("SELECT COUNT(*) FROM events;")
    event_count = cursor.fetchone()[0]
    assert event_count == 7, f"Expected 7 events to remain, found {event_count}"

    cursor.execute("SELECT user_id, username FROM users ORDER BY user_id")
    assert cursor.fetchall() == [(1, 'alice'), (2, 'bob')], "The users table contents were modified."

    cursor.execute("SELECT event_id, user_id, event_date, score, comment FROM events ORDER BY event_id")
    assert cursor.fetchall() == [
        (101, 1, '2023-01-01', 10.0, 'First event'),
        (102, 1, '2023-01-03', 20.0, 'Second event\nwith newline'),
        (103, 1, '2023-01-05', 30.0, 'Third event'),
        (104, 1, '2023-01-07', 40.0, 'Fourth event'),
        (201, 2, '2023-01-02', 15.0, 'Bob first'),
        (202, 2, '2023-01-04', 25.0, 'Bob second\nline2\nline3'),
        (203, 2, '2023-01-06', 5.0, 'Bob third'),
    ], "The events table contents were modified."

    conn.close()


def test_rust_project_and_dynamic_execution():
    assert os.path.isdir(PROJECT_PATH), "The Rust project directory /home/user/etl is missing."
    assert os.path.isfile(MANIFEST_PATH), "The Rust project has no Cargo.toml."

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST_PATH],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Invalid Cargo project:\n{metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    binary_targets = [
        target
        for package in metadata.get("packages", [])
        for target in package.get("targets", [])
        if "bin" in target.get("kind", []) and target.get("src_path", "").endswith(".rs")
    ]
    assert binary_targets, "The Cargo project does not contain a Rust binary target."

    users = [(10, "carol"), (20, "dave")]
    events = [
        (1001, 10, "2024-03-01", 2.17, "first\nembedded newline"),
        (1002, 10, "2024-03-04", 5.41, "second"),
        (1003, 10, "2024-03-09", 8.92, "third\nline two\nline three"),
        (1004, 10, "2024-03-15", -1.20, "fourth"),
        (2001, 20, "2024-02-02", 7.71, "alpha"),
        (2002, 20, "2024-02-08", 0.17, "beta\ncontinued"),
        (2003, 20, "2024-02-20", 3.35, "gamma"),
    ]

    usernames = dict(users)
    expected = []
    for user_id in sorted(usernames):
        ordered = sorted((event for event in events if event[1] == user_id), key=lambda event: event[2])
        prior_scores = []
        for event in ordered:
            prior_scores.append(Decimal(str(event[3])))
            window = prior_scores[-3:]
            average = (sum(window) / Decimal(len(window))).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            expected.append((user_id, usernames[user_id], event[2], float(average)))

    backup_dir = tempfile.mkdtemp(prefix="etl-verifier-")
    backup_path = os.path.join(backup_dir, "data.db")
    shutil.copy2(DB_PATH, backup_path)

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("DROP TABLE IF EXISTS rolling_stats")
        cursor.execute("DELETE FROM events")
        cursor.execute("DELETE FROM users")
        cursor.executemany("INSERT INTO users (user_id, username) VALUES (?, ?)", users)
        cursor.executemany(
            "INSERT INTO events (event_id, user_id, event_date, score, comment) VALUES (?, ?, ?, ?, ?)",
            events,
        )
        conn.commit()
        conn.close()

        run_result = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", MANIFEST_PATH],
            cwd=PROJECT_PATH,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        assert run_result.returncode == 0, (
            "The Rust ETL application failed when executed.\n"
            f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
        )

        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT user_id, username FROM users ORDER BY user_id")
        assert cursor.fetchall() == users, "The Rust application modified the users table."
        cursor.execute("SELECT event_id, user_id, event_date, score, comment FROM events ORDER BY event_id")
        assert cursor.fetchall() == events, "The Rust application modified the events table."
        cursor.execute(
            "SELECT user_id, username, event_date, rolling_avg "
            "FROM rolling_stats ORDER BY user_id ASC, event_date ASC"
        )
        actual = cursor.fetchall()
        conn.close()

        assert len(actual) == len(expected), f"Dynamic run expected {len(expected)} rows, found {len(actual)}."
        for index, (actual_row, expected_row) in enumerate(zip(actual, expected), 1):
            assert actual_row[:3] == expected_row[:3], (
                f"Dynamic row {index}: expected {expected_row[:3]}, got {actual_row[:3]}"
            )
            assert abs(actual_row[3] - expected_row[3]) < 1e-5, (
                f"Dynamic row {index}: expected rolling_avg {expected_row[3]}, got {actual_row[3]}"
            )
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(backup_path, DB_PATH)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
