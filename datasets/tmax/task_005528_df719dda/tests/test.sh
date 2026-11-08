#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import json
import os
import random
import secrets
import sqlite3
import subprocess
from collections import defaultdict

DB_PATH = "/home/user/threat_activity.db"
SOURCE_PATH = "/home/user/analyze.go"
ACCESS_PATH = "/home/user/access.log"
THREAT_PATH = "/home/user/threat_ips.csv"


def test_database_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} was not created."


def test_database_contents():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='activity_summary';")
    assert cursor.fetchone() is not None, "Table 'activity_summary' does not exist in the database."

    cursor.execute("SELECT bucket_time, ip, request_count FROM activity_summary ORDER BY bucket_time, ip;")
    rows = cursor.fetchall()

    expected_rows = [
        ("2023-10-01T10:00:00Z", "10.0.0.5", 3),
        ("2023-10-01T10:00:00Z", "10.0.0.9", 1),
        ("2023-10-01T10:05:00Z", "10.0.0.5", 1),
        ("2023-10-01T10:05:00Z", "10.0.0.9", 1),
        ("2023-10-01T10:10:00Z", "10.0.0.9", 1)
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in 'activity_summary', but got {len(rows)}."

    for i, (expected, actual) in enumerate(zip(expected_rows, rows)):
        assert expected == actual, f"Row {i+1} mismatch. Expected {expected}, got {actual}."

    conn.close()


def test_go_program_executes_pipeline_on_fresh_inputs():
    assert os.path.isfile(SOURCE_PATH), f"Go source file {SOURCE_PATH} does not exist."

    listed = subprocess.run(
        ["go", "list", "-json", "analyze.go"],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert listed.returncode == 0, f"analyze.go is not a valid Go main package:\n{listed.stdout}\n{listed.stderr}"
    package = json.loads(listed.stdout)
    assert package.get("Name") == "main", "analyze.go must define a Go main package."
    assert "github.com/mattn/go-sqlite3" in package.get("Imports", []), \
        "analyze.go must import github.com/mattn/go-sqlite3."

    originals = {
        ACCESS_PATH: open(ACCESS_PATH, "rb").read(),
        THREAT_PATH: open(THREAT_PATH, "rb").read(),
        DB_PATH: open(DB_PATH, "rb").read(),
    }

    try:
        token = secrets.randbelow(180) + 20
        threat_a = f"10.41.{token}.7"
        threat_b = f"172.23.{token}.19"
        benign = f"192.168.{token}.33"
        threat_ips = {threat_a, threat_b}

        base_epoch = 1609459200 + secrets.randbelow(4 * 365 * 24 * 60) * 60
        base_epoch -= base_epoch % 300
        count_a = 2 + secrets.randbelow(4)
        count_b = 1 + secrets.randbelow(3)

        events = []
        for i in range(count_a):
            events.append({"ts_epoch": base_epoch + 10 + i, "ip": threat_a, "status": 401})
        events.extend([
            {"ts_epoch": base_epoch + 301, "ip": threat_a, "status": 403},
            {"ts_epoch": base_epoch + 499, "ip": threat_a, "status": 403},
        ])
        for i in range(count_b):
            events.append({"ts_epoch": base_epoch + 200 + i, "ip": threat_b, "status": 500})
        events.extend([
            {"ts_epoch": base_epoch + 300, "ip": threat_b, "status": 500},
            {"ts_epoch": base_epoch + 600, "ip": threat_b, "status": 500},
            {"ts_epoch": base_epoch + 42, "ip": benign, "status": 200},
            {"ts_epoch": base_epoch + 602, "ip": benign, "status": 200},
        ])
        random.SystemRandom().shuffle(events)

        expected_counts = defaultdict(int)
        serialized = []
        for event in events:
            timestamp = datetime.datetime.fromtimestamp(event["ts_epoch"], datetime.timezone.utc)
            ts_text = timestamp.strftime("%Y-%m-%dT%H:%M:%SZ")
            serialized.append(json.dumps({"ts": ts_text, "ip": event["ip"], "status": event["status"]}))
            if event["ip"] in threat_ips:
                bucket_epoch = event["ts_epoch"] - event["ts_epoch"] % 300
                bucket = datetime.datetime.fromtimestamp(bucket_epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                expected_counts[(bucket, event["ip"])] += 1

        with open(ACCESS_PATH, "w", encoding="utf-8") as access_file:
            access_file.write("\n".join(serialized) + "\n")
        with open(THREAT_PATH, "w", newline="", encoding="utf-8") as threat_file:
            writer = csv.writer(threat_file)
            writer.writerow([threat_a, "97"])
            writer.writerow([threat_b, "83"])
        os.remove(DB_PATH)

        result = subprocess.run(
            ["go", "run", "analyze.go"],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=120,
        )
        assert result.returncode == 0, f"Running analyze.go failed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(DB_PATH), "analyze.go did not create threat_activity.db."

        conn = sqlite3.connect(DB_PATH)
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='activity_summary';")
            assert cursor.fetchone() is not None, "analyze.go did not create activity_summary."
            cursor.execute("SELECT bucket_time, ip, request_count FROM activity_summary ORDER BY bucket_time, ip;")
            actual = cursor.fetchall()
        finally:
            conn.close()

        expected = sorted((bucket, ip, count) for (bucket, ip), count in expected_counts.items())
        assert actual == expected, f"Fresh-input pipeline result mismatch. Expected {expected}, got {actual}."
    finally:
        for path, contents in originals.items():
            with open(path, "wb") as restored:
                restored.write(contents)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
