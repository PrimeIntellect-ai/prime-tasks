#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import sqlite3
import stat
import subprocess
import tempfile
import uuid


def test_error_log_verification():
    log_path = "/home/user/etl_errors.log"
    assert os.path.isfile(log_path), f"Error log file {log_path} is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {log_path}, found {len(lines)}."
    assert "evt_004" in lines, "evt_004 is missing from the error log."
    assert "evt_008" in lines, "evt_008 is missing from the error log."


def test_database_state_verification():
    db_path = "/home/user/data.db"
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT count(*) FROM events;")
    count = cursor.fetchone()[0]
    assert count == 5, f"Expected exactly 5 rows in events table, found {count}."

    expected_data = {
        "evt_001": {"hour": 14, "is_weekend": 0},
        "evt_003": {"hour": 9, "is_weekend": 1},
        "evt_005": {"hour": 23, "is_weekend": 1},
        "evt_006": {"hour": 10, "is_weekend": 0},
        "evt_009": {"hour": 2, "is_weekend": 1},
    }

    cursor.execute("SELECT event_id, hour, is_weekend FROM events;")
    rows = cursor.fetchall()

    for event_id, hour, is_weekend in rows:
        assert event_id in expected_data, f"Unexpected event_id {event_id} found in database."
        expected_hour = expected_data[event_id]["hour"]
        expected_weekend = expected_data[event_id]["is_weekend"]

        assert hour == expected_hour, f"Expected hour {expected_hour} for {event_id}, got {hour}."

        is_weekend_int = 1 if is_weekend in (1, '1', 'true', 'True', True) else 0
        assert is_weekend_int == expected_weekend, f"Expected is_weekend={expected_weekend} for {event_id}, got {is_weekend}."

    expected_full = {
        "evt_001": ("user_123A", "click", "2023-10-25T14:30:00Z", 14, 0),
        "evt_003": ("user_789B", "click", "2023-10-28T09:15:00Z", 9, 1),
        "evt_005": ("user_111B", "view", "2023-10-29T23:45:00Z", 23, 1),
        "evt_006": ("user_222A", "click", "2023-10-26T10:00:00Z", 10, 0),
        "evt_009": ("user_555A", "purchase", "2023-10-21T02:00:00Z", 2, 1),
    }
    cursor.execute("SELECT event_id, user_id, event_type, timestamp, hour, is_weekend FROM events")
    actual_full = {row[0]: (row[1], row[2], row[3], row[4], int(row[5])) for row in cursor.fetchall()}
    assert actual_full == expected_full

    conn.close()


def test_csv_export_verification():
    csv_path = "/home/user/final_export.csv"
    assert os.path.isfile(csv_path), f"Exported CSV file {csv_path} is missing."

    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 6, f"Expected 6 rows (1 header + 5 data) in {csv_path}, found {len(rows)}."

    header = rows[0]
    assert "event_id" in header, "Header row is missing 'event_id' column."

    event_ids = {row[0] for row in rows[1:]}
    expected_event_ids = {"evt_001", "evt_003", "evt_005", "evt_006", "evt_009"}
    assert event_ids == expected_event_ids, f"Exported CSV does not contain the expected event IDs. Got {event_ids}."

    expected_header = ["event_id", "user_id", "event_type", "timestamp", "hour", "is_weekend"]
    assert header == expected_header, f"Expected CSV header {expected_header}, got {header}."
    expected_rows = {
        "evt_001": ["user_123A", "click", "2023-10-25T14:30:00Z", "14", "0"],
        "evt_003": ["user_789B", "click", "2023-10-28T09:15:00Z", "9", "1"],
        "evt_005": ["user_111B", "view", "2023-10-29T23:45:00Z", "23", "1"],
        "evt_006": ["user_222A", "click", "2023-10-26T10:00:00Z", "10", "0"],
        "evt_009": ["user_555A", "purchase", "2023-10-21T02:00:00Z", "2", "1"],
    }
    actual_rows = {}
    for row in rows[1:]:
        assert len(row) == 6, f"Expected 6 columns, got row {row}."
        boolean = "1" if row[5] in ("1", "true", "True") else "0"
        actual_rows[row[0]] = [row[1], row[2], row[3], row[4], boolean]
    assert actual_rows == expected_rows


def test_etl_program_behavior_on_derived_input():
    etl_path = "/home/user/etl.go"
    assert os.path.lexists(etl_path), f"{etl_path} is missing."
    assert stat.S_ISREG(os.lstat(etl_path).st_mode), f"{etl_path} must be a regular Go source file."

    managed = [
        "/home/user/source.csv",
        "/home/user/data.db",
        "/home/user/etl_errors.log",
        "/home/user/final_export.csv",
    ]
    backups = {}
    for path in managed:
        backups[path] = open(path, "rb").read() if os.path.isfile(path) else None

    token = uuid.uuid4().hex[:12]
    e1 = f"dyn_{token}_1"
    e2 = f"dyn_{token}_2"
    e3 = f"dyn_{token}_3"
    bad = f"dyn_{token}_bad"
    nonsampled = f"dyn_{token}_skip"
    seed = f"dyn_{token}_seed"
    sentinel = f"dyn_{token}_prior_error"

    binary = tempfile.mktemp(prefix="etl-verifier-")
    try:
        conn = sqlite3.connect("/home/user/data.db")
        conn.execute("DROP TABLE IF EXISTS events")
        conn.execute("CREATE TABLE events (event_id TEXT PRIMARY KEY, user_id TEXT, event_type TEXT, timestamp TEXT, hour INTEGER, is_weekend BOOLEAN)")
        conn.execute("INSERT INTO events VALUES (?, ?, ?, ?, ?, ?)",
                     (e1, "stale_userA", "stale", "2000-01-01T00:00:00Z", 0, 0))
        conn.execute("INSERT INTO events VALUES (?, ?, ?, ?, ?, ?)",
                     (seed, "existing_userZ", "existing", "2020-01-01T01:00:00Z", 1, 0))
        conn.commit()
        conn.close()

        with open("/home/user/etl_errors.log", "w") as f:
            f.write(sentinel + "\n")

        with open("/home/user/source.csv", "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["event_id", "user_id", "event_type", "timestamp"])
            writer.writerow([e1, "dynamic_11A", "click", "2024-01-06T03:04:05Z"])
            writer.writerow([e2, "dynamic_22B", "view", "2024-01-08T17:20:00Z"])
            writer.writerow([bad, "dynamic_33A", "bad", "not-rfc3339"])
            writer.writerow([nonsampled, "dynamic_44C", "ignored", "also-not-rfc3339"])

        subprocess.run(
            ["go", "build", "-o", binary, etl_path],
            cwd="/home/user", check=True, capture_output=True, text=True, timeout=120
        )
        subprocess.run([binary], cwd="/home/user", check=True, capture_output=True, text=True, timeout=30)

        with open("/home/user/etl_errors.log") as f:
            assert [line.strip() for line in f if line.strip()] == [sentinel, bad]

        with open("/home/user/source.csv", "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["event_id", "user_id", "event_type", "timestamp"])
            writer.writerow([e1, "dynamic_11A", "updated", "2024-01-07T22:10:00Z"])
            writer.writerow([e2, "dynamic_22B", "view", "2024-01-08T17:20:00Z"])
            writer.writerow([e3, "dynamic_55B", "purchase", "2024-01-09T05:00:00Z"])
            writer.writerow([bad, "dynamic_33A", "bad", "not-rfc3339"])
            writer.writerow([nonsampled, "dynamic_44C", "ignored", "also-not-rfc3339"])

        subprocess.run([binary], cwd="/home/user", check=True, capture_output=True, text=True, timeout=30)

        with open("/home/user/etl_errors.log") as f:
            assert [line.strip() for line in f if line.strip()] == [sentinel, bad, bad]

        conn = sqlite3.connect("/home/user/data.db")
        rows = conn.execute(
            "SELECT event_id, user_id, event_type, timestamp, hour, is_weekend FROM events"
        ).fetchall()
        conn.close()
        actual = {row[0]: (row[1], row[2], row[3], row[4], int(row[5])) for row in rows}
        expected = {
            seed: ("existing_userZ", "existing", "2020-01-01T01:00:00Z", 1, 0),
            e1: ("dynamic_11A", "updated", "2024-01-07T22:10:00Z", 22, 1),
            e2: ("dynamic_22B", "view", "2024-01-08T17:20:00Z", 17, 0),
            e3: ("dynamic_55B", "purchase", "2024-01-09T05:00:00Z", 5, 0),
        }
        assert actual == expected
        assert bad not in actual and nonsampled not in actual
    finally:
        if os.path.exists(binary):
            os.remove(binary)
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
