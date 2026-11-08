#!/bin/bash
set -e
mkdir -p /logs/verifier
DB=/home/user/compliance.db
BACKUP=/tmp/compliance.db.original
cp "$DB" "$BACKUP"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess
from collections import defaultdict
from pathlib import Path

import pytest

OUTPUT_PATH = "/home/user/flagged_events.json"
PROJECT_PATH = Path("/home/user/auditor")
DB_PATH = "/home/user/compliance.db"


def run_auditor():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT_PATH / "Cargo.toml")],
        cwd=str(PROJECT_PATH),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        "The Rust auditor failed to run.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        f"Output file not found at {OUTPUT_PATH}. Did your Rust program run and create it?"
    )


def load_output():
    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT_PATH} does not contain valid JSON.")


def test_rust_project_and_required_implementation_exist():
    assert PROJECT_PATH.is_dir(), "The /home/user/auditor Rust project does not exist."
    assert (PROJECT_PATH / "Cargo.toml").is_file(), "Cargo.toml is missing from the auditor project."
    rust_files = list(PROJECT_PATH.rglob("*.rs"))
    assert rust_files, "No Rust source files were found in the auditor project."
    source = "\n".join(path.read_text(errors="replace") for path in rust_files)
    assert re.search(r"\bover\b", source, re.IGNORECASE), (
        "The Rust application's SQL must use a window function (OVER)."
    )
    assert "role_graph" in source.lower(), (
        "The Rust application does not read/materialize the role_graph."
    )


def test_flagged_events_file_exists():
    """Test that the output JSON file was created at the correct path."""
    run_auditor()
    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}. Did your Rust program run and create it?"


def test_flagged_events_content():
    """Test that the output JSON file contains the correct flagged events in the correct order."""
    data = load_output()
    assert isinstance(data, list), "The JSON root must be an array (list)."
    assert len(data) == 2, f"Expected exactly 2 flagged events, but found {len(data)}."

    expected_events = [
        {"event_id": 16, "user_id": "u1", "role_assumed": "manager"},
        {"event_id": 4, "user_id": "u1", "role_assumed": "admin"}
    ]

    for i, expected in enumerate(expected_events):
        actual = data[i]
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        for key in expected:
            assert key in actual, f"Missing key '{key}' in item at index {i}."
            assert actual[key] == expected[key], f"Expected {key} to be {expected[key]} at index {i}, but got {actual[key]}."


def derive_expected(conn):
    users = dict(conn.execute("SELECT user_id, base_role FROM users"))
    graph = defaultdict(set)
    for parent, child in conn.execute("SELECT parent_role, child_role FROM role_graph"):
        graph[parent].add(child)

    reachable = {}
    for user_id, base_role in users.items():
        seen = {base_role}
        stack = [base_role]
        while stack:
            role = stack.pop()
            for child in graph[role]:
                if child not in seen:
                    seen.add(child)
                    stack.append(child)
        reachable[user_id] = seen

    by_user = defaultdict(list)
    rows = conn.execute(
        "SELECT event_id, timestamp, user_id, role_assumed, status FROM events"
    ).fetchall()
    for row in rows:
        by_user[row[2]].append(row)

    flagged = []
    for user_id, events in by_user.items():
        events.sort(key=lambda row: row[1])
        for index, row in enumerate(events):
            event_id, timestamp, _, role, status = row
            previous = events[max(0, index - 5):index]
            failures = sum(1 for item in previous if item[4] == "FAILURE")
            if status == "SUCCESS" and failures >= 3 and role not in reachable[user_id]:
                flagged.append((timestamp, {
                    "event_id": event_id,
                    "user_id": user_id,
                    "role_assumed": role,
                }))

    flagged.sort(key=lambda item: item[0], reverse=True)
    return [item[1] for item in flagged[:10]]


def create_dynamic_database():
    token = secrets.token_hex(6)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        DROP TABLE IF EXISTS users;
        DROP TABLE IF EXISTS role_graph;
        DROP TABLE IF EXISTS events;
        CREATE TABLE users (user_id TEXT, base_role TEXT);
        CREATE TABLE role_graph (parent_role TEXT, child_role TEXT);
        CREATE TABLE events (
            event_id INTEGER,
            timestamp INTEGER,
            user_id TEXT,
            role_assumed TEXT,
            status TEXT
        );
    """)

    event_id = 700000
    timestamp = 50000

    def add_event(user, role, status):
        nonlocal event_id, timestamp
        event_id += 7
        timestamp += 11
        conn.execute(
            "INSERT INTO events VALUES (?, ?, ?, ?, ?)",
            (event_id, timestamp, user, role, status),
        )

    # Twelve genuine escalations verify sorting and the top-ten limit.
    for i in range(12):
        user = f"sus_{token}_{i}"
        base = f"base_{token}_{i}"
        bad = f"forbidden_{token}_{i}"
        conn.execute("INSERT INTO users VALUES (?, ?)", (user, base))
        for _ in range(3):
            add_event(user, bad, "FAILURE")
        add_event(user, bad, "SUCCESS")

    # A long transitive path must be recognized as reachable.
    user = f"reachable_{token}"
    chain = [f"chain_{token}_{i}" for i in range(18)]
    conn.execute("INSERT INTO users VALUES (?, ?)", (user, chain[0]))
    conn.executemany("INSERT INTO role_graph VALUES (?, ?)", zip(chain, chain[1:]))
    for _ in range(4):
        add_event(user, chain[-1], "FAILURE")
    add_event(user, chain[-1], "SUCCESS")

    # The base role is reachable from itself.
    user = f"self_{token}"
    base = f"self_role_{token}"
    conn.execute("INSERT INTO users VALUES (?, ?)", (user, base))
    for _ in range(3):
        add_event(user, base, "FAILURE")
    add_event(user, base, "SUCCESS")

    # Two failures are insufficient.
    user = f"two_{token}"
    base = f"two_base_{token}"
    bad = f"two_bad_{token}"
    conn.execute("INSERT INTO users VALUES (?, ?)", (user, base))
    for _ in range(2):
        add_event(user, bad, "FAILURE")
    add_event(user, bad, "SUCCESS")

    # Failures older than the immediately preceding five events do not count.
    user = f"old_{token}"
    base = f"old_base_{token}"
    bad = f"old_bad_{token}"
    conn.execute("INSERT INTO users VALUES (?, ?)", (user, base))
    for _ in range(3):
        add_event(user, bad, "FAILURE")
    for _ in range(5):
        add_event(user, base, "SUCCESS")
    add_event(user, bad, "SUCCESS")

    conn.commit()
    expected = derive_expected(conn)
    conn.close()
    return expected


def test_auditor_on_unseen_database():
    expected = create_dynamic_database()
    assert len(expected) == 10
    run_auditor()
    actual = load_output()
    assert isinstance(actual, list), "The JSON root must be an array (list)."
    assert actual == expected, (
        "The executed Rust auditor produced incorrect results for an unseen database. "
        "It must use each user's five preceding events and Rust graph reachability, then return the ten most recent matches."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
else
    reward=0
fi

cp "$BACKUP" "$DB"
echo "$reward" > /logs/verifier/reward.txt
