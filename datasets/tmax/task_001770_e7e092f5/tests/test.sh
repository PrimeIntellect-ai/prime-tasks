#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import stat
import subprocess
import sys
from collections import deque

import pytest

SCRIPT_PATH = '/home/user/audit.py'
CSV_PATH = '/home/user/delegations.csv'
REPORT_PATH = '/home/user/audit_report.json'


def load_report():
    assert os.path.isfile(REPORT_PATH), f"The file {REPORT_PATH} does not exist. Did you run the script?"
    with open(REPORT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")


def assert_original_report(data):
    assert "total_unique_users" in data, "The key 'total_unique_users' is missing from the JSON output."
    assert "shortest_path" in data, "The key 'shortest_path' is missing from the JSON output."
    assert data["total_unique_users"] == 16, f"Expected 16 unique users, but got {data['total_unique_users']}."

    expected_path = ["User_Charlie", "User_Hotel", "User_Zulu"]
    assert data["shortest_path"] == expected_path, f"Expected shortest path {expected_path}, but got {data['shortest_path']}."


def run_script():
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"audit.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def shortest_distance(edges, start, target):
    graph = {}
    for source, destination in edges:
        graph.setdefault(source, []).append(destination)
    queue = deque([(start, 0)])
    seen = {start}
    while queue:
        node, distance = queue.popleft()
        if node == target:
            return distance
        for neighbor in graph.get(node, []):
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, distance + 1))
    return None


def test_01_existing_report_and_script():
    assert os.path.exists(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist."
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} must be a regular Python script."

    data = load_report()
    assert_original_report(data)


def test_02_script_runs_on_original_input():
    os.remove(REPORT_PATH)
    run_script()
    data = load_report()
    assert_original_report(data)


def test_03_script_reconstructs_graph_from_csv():
    token = secrets.token_hex(6)
    a = f"Audit_{token}_A"
    b = f"Audit_{token}_B"
    c = f"Audit_{token}_C"
    d = f"Audit_{token}_D"
    e = f"Audit_{token}_E"
    x = f"Audit_{token}_X"
    y = f"Audit_{token}_Y"

    edges = [
        ("User_Charlie", a),
        (a, b),
        (b, "User_Zulu"),
        ("User_Charlie", c),
        (c, d),
        (d, e),
        (e, "User_Zulu"),
        (x, y),
        (y, x),
        (a, b),
    ]

    csv_backup = CSV_PATH + '.verifier_backup'
    report_backup = REPORT_PATH + '.verifier_backup'
    shutil.copyfile(CSV_PATH, csv_backup)
    if os.path.exists(REPORT_PATH):
        shutil.copyfile(REPORT_PATH, report_backup)

    try:
        with open(CSV_PATH, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['delegator', 'delegatee', 'timestamp'])
            for index, (source, destination) in enumerate(edges):
                writer.writerow([source, destination, f'2026-01-02T03:04:{index:02d}Z'])

        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        run_script()
        data = load_report()

        assert set(data.keys()) == {'total_unique_users', 'shortest_path'}, "The JSON output does not have the required exact schema."
        expected_users = {user for edge in edges for user in edge}
        assert type(data['total_unique_users']) is int, "total_unique_users must be an integer."
        assert data['total_unique_users'] == len(expected_users), (
            f"Expected {len(expected_users)} unique users for the supplied CSV, "
            f"but got {data['total_unique_users']}."
        )

        path = data['shortest_path']
        assert isinstance(path, list), "shortest_path must be a JSON array."
        assert path and path[0] == 'User_Charlie' and path[-1] == 'User_Zulu', (
            "shortest_path must run from User_Charlie to User_Zulu."
        )
        edge_set = set(edges)
        assert all((source, destination) in edge_set for source, destination in zip(path, path[1:])), (
            "shortest_path contains a delegation edge not present in delegations.csv."
        )
        expected_distance = shortest_distance(edges, 'User_Charlie', 'User_Zulu')
        assert len(path) - 1 == expected_distance, (
            f"Expected a shortest path of {expected_distance} edges, but got {len(path) - 1}."
        )
    finally:
        shutil.move(csv_backup, CSV_PATH)
        if os.path.exists(report_backup):
            shutil.move(report_backup, REPORT_PATH)
        elif os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
