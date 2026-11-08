#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from collections import Counter, defaultdict

import pytest

SUMMARY_PATH = Path("/home/user/access_summary.json")
SCRIPT_PATH = Path("/home/user/analyze_access.py")
DB_PATH = Path("/home/user/access_graph.db")
EXPECTED = None


def database_snapshot():
    raw_hash = hashlib.sha256(DB_PATH.read_bytes()).hexdigest()
    with sqlite3.connect(DB_PATH) as conn:
        logical_dump = "\n".join(conn.iterdump())
    return raw_hash, logical_dump


def derive_expected():
    with sqlite3.connect(DB_PATH) as conn:
        nodes = dict(conn.execute("SELECT id, label FROM nodes"))
        edges = list(conn.execute("SELECT source, target, relation FROM edges"))

    has_role = defaultdict(list)
    can_access = defaultdict(list)
    connects_to = defaultdict(list)
    for source, target, relation in edges:
        if relation == "HAS_ROLE":
            has_role[source].append(target)
        elif relation == "CAN_ACCESS":
            can_access[source].append(target)
        elif relation == "CONNECTS_TO":
            connects_to[source].append(target)

    expected = []
    users = sorted(node_id for node_id, label in nodes.items() if label == "User")

    for user in users:
        # Counts preserve distinct semantic prefixes, including duplicate edge rows.
        frontier = Counter()
        for role in has_role[user]:
            if nodes.get(role) != "Role":
                continue
            for server in can_access[role]:
                if nodes.get(server) == "Server":
                    frontier[server] += 1

        visited_servers = set(frontier)
        connect_hops = 0
        result = None

        while frontier:
            connect_hops += 1
            next_frontier = Counter()
            database_path_count = 0

            for source, prefix_count in frontier.items():
                for target in connects_to[source]:
                    target_label = nodes.get(target)
                    if target_label == "SecureDatabase":
                        database_path_count += prefix_count
                    elif target_label == "Server" and target not in visited_servers:
                        next_frontier[target] += prefix_count

            if database_path_count:
                result = {
                    "user": user,
                    "min_hops": 2 + connect_hops,
                    "shortest_path_count": database_path_count,
                }
                break

            visited_servers.update(next_frontier)
            frontier = next_frontier

        if result is not None:
            expected.append(result)

    return expected


def test_script_exists():
    assert SCRIPT_PATH.exists(), f"The script {SCRIPT_PATH} does not exist."
    assert SCRIPT_PATH.is_file(), f"The script {SCRIPT_PATH} is not a regular file."


def test_script_executes_and_preserves_database():
    global EXPECTED
    EXPECTED = derive_expected()
    before = database_snapshot()

    if SUMMARY_PATH.exists() or SUMMARY_PATH.is_symlink():
        SUMMARY_PATH.unlink()

    try:
        completed = subprocess.run(
            ["python3", str(SCRIPT_PATH)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("analyze_access.py timed out after 30 seconds.")

    assert completed.returncode == 0, (
        "analyze_access.py exited unsuccessfully.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert SCRIPT_PATH.is_file(), f"The script {SCRIPT_PATH} was removed during execution."
    assert database_snapshot() == before, "The original SQLite database was modified."


def test_access_summary_exists():
    assert SUMMARY_PATH.exists(), f"The output file {SUMMARY_PATH} does not exist."
    assert SUMMARY_PATH.is_file(), f"The output path {SUMMARY_PATH} is not a regular file."


def test_access_summary_content():
    with SUMMARY_PATH.open("r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {SUMMARY_PATH} does not contain valid JSON.")

    assert EXPECTED is not None, "Expected results were not derived."
    expected = EXPECTED

    assert isinstance(data, list), (
        f"Expected the JSON output to be a list, but got {type(data).__name__}."
    )
    assert len(data) == len(expected), (
        f"Expected {len(expected)} users in the output, but found {len(data)}."
    )

    users_in_data = [item.get("user") for item in data]
    assert users_in_data == sorted(users_in_data), (
        "The JSON array is not sorted alphabetically by the 'user' key."
    )

    for expected_item, actual_item in zip(expected, data):
        assert actual_item.get("user") == expected_item["user"], (
            f"Expected user {expected_item['user']}, but got {actual_item.get('user')}."
        )
        assert actual_item.get("min_hops") == expected_item["min_hops"], (
            f"Incorrect min_hops for {expected_item['user']}. "
            f"Expected {expected_item['min_hops']}, got {actual_item.get('min_hops')}."
        )
        assert actual_item.get("shortest_path_count") == expected_item["shortest_path_count"], (
            f"Incorrect shortest_path_count for {expected_item['user']}. "
            f"Expected {expected_item['shortest_path_count']}, "
            f"got {actual_item.get('shortest_path_count')}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
