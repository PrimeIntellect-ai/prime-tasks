#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import sqlite3
import subprocess
import sys
import tempfile

import pytest

OUTPUT_PATH = "/home/user/max_rolling.json"
SCRIPT_PATH = "/home/user/etl.py"
DB_PATH = "/home/user/users.db"
EVENTS_PATH = "/home/user/events.jsonl"


def test_max_rolling_json_exists_and_correct():
    assert os.path.isfile(OUTPUT_PATH), (
        f"Output file {OUTPUT_PATH} is missing. Did you run your script and save the output?"
    )

    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT_PATH} does not contain valid JSON.")

    expected_data = {"1": 25, "3": 5, "4": 150}
    assert isinstance(data, dict), (
        f"The JSON in {OUTPUT_PATH} should be a dictionary mapping user IDs to integers."
    )
    assert data == expected_data, (
        f"The content of {OUTPUT_PATH} does not match the expected output. "
        f"Expected {expected_data}, but got {data}."
    )


def test_etl_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."


def test_etl_script_processes_fresh_inputs():
    rng = random.SystemRandom()
    user_ids = rng.sample(range(1000, 1000000), 4)
    active_a, inactive, active_b, active_c = user_ids

    users = [
        (active_a, "fresh_a", 1),
        (inactive, "fresh_inactive", 0),
        (active_b, "fresh_b", 1),
        (active_c, "fresh_c", 1),
    ]

    a_points = [rng.randint(11, 40), -rng.randint(2, 15), rng.randint(45, 80), rng.randint(5, 25)]
    b_point = -rng.randint(20, 60)
    c_points = [rng.randint(3, 20), rng.randint(25, 55), -rng.randint(1, 10)]

    events = [
        {"user_id": active_a, "timestamp": "2042-05-01T10:20:00Z", "points": a_points[2]},
        {"user_id": inactive, "timestamp": "2042-05-01T10:01:00Z", "points": rng.randint(5000, 9000)},
        {"user_id": active_c, "timestamp": "2042-05-03T09:30:00Z", "points": c_points[2]},
        {"user_id": active_a, "timestamp": "2042-05-01T10:00:00Z", "points": a_points[0]},
        {"user_id": active_b, "timestamp": "2042-05-02T11:00:00Z", "points": b_point},
        {"user_id": active_c, "timestamp": "2042-05-03T09:00:00Z", "points": c_points[0]},
        {"user_id": active_a, "timestamp": "2042-05-01T10:30:00Z", "points": a_points[3]},
        {"user_id": active_c, "timestamp": "2042-05-03T09:15:00Z", "points": c_points[1]},
        {"user_id": active_a, "timestamp": "2042-05-01T10:10:00Z", "points": a_points[1]},
    ]

    active_ids = {row[0] for row in users if row[2]}
    grouped = {}
    for event in events:
        if event["user_id"] in active_ids:
            grouped.setdefault(event["user_id"], []).append(event)

    expected = {}
    for user_id, user_events in grouped.items():
        ordered = sorted(user_events, key=lambda event: event["timestamp"])
        rolling = []
        for index, event in enumerate(ordered):
            total = event["points"]
            if index > 0:
                total += ordered[index - 1]["points"]
            rolling.append(total)
        expected[str(user_id)] = max(rolling)

    backup_dir = tempfile.mkdtemp(prefix="etl-verifier-")
    paths = [DB_PATH, EVENTS_PATH, OUTPUT_PATH]
    existed = {path: os.path.exists(path) for path in paths}
    for path in paths:
        if existed[path]:
            shutil.copy2(path, os.path.join(backup_dir, os.path.basename(path)))

    try:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        connection = sqlite3.connect(DB_PATH)
        try:
            connection.execute(
                "CREATE TABLE users (user_id INTEGER PRIMARY KEY, username TEXT, is_active INTEGER)"
            )
            connection.executemany(
                "INSERT INTO users (user_id, username, is_active) VALUES (?, ?, ?)", users
            )
            connection.commit()
        finally:
            connection.close()

        with open(EVENTS_PATH, "w") as event_file:
            for event in events:
                event_file.write(json.dumps(event) + "\n")

        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Running {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(OUTPUT_PATH), "The script did not create max_rolling.json when rerun."

        with open(OUTPUT_PATH, "r") as output_file:
            actual = json.load(output_file)
        assert isinstance(actual, dict), "The generated JSON must be an object."
        assert actual == expected, f"Fresh-input result was incorrect: expected {expected}, got {actual}."
        assert all(isinstance(value, int) and not isinstance(value, bool) for value in actual.values()), (
            "All output values must be integers."
        )
    finally:
        for path in paths:
            if existed[path]:
                shutil.copy2(os.path.join(backup_dir, os.path.basename(path)), path)
            elif os.path.exists(path):
                os.remove(path)
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
