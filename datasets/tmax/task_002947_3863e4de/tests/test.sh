#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import sqlite3
import statistics
import subprocess
import sys
import tempfile

import pytest

DB_PATH = "/home/user/telemetry_recovered.db"
TRIAGE_PATH = "/home/user/triage.py"
ANOMALIES_PATH = "/home/user/anomalies.txt"


def expected_original_rows():
    random.seed(42)
    expected = {}

    for row_id in range(1, 101):
        temp = random.normalvariate(20.0, 2.0)
        expected[row_id] = json.dumps(
            {"temp": temp, "status": "ok"}
        ).encode("utf-8")

    for row_id in range(101, 121):
        if row_id in (105, 112, 118):
            temp = 85.0 + random.random() * 10
        else:
            temp = random.normalvariate(20.0, 2.0)

        expected[row_id] = json.dumps(
            {"temp": temp, "status": "legacy", "note": "t\u00b0"}
        ).encode("latin-1")

    return expected


def read_rows(db_path):
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, payload FROM readings")
        return cur.fetchall()
    finally:
        conn.close()


def expected_anomalies_from_rows(rows):
    temps = []
    parsed_data = []

    for row_id, payload in rows:
        try:
            payload_str = payload.decode("utf-8")
        except UnicodeDecodeError:
            payload_str = payload.decode("latin-1")

        data = json.loads(payload_str)
        temp = data["temp"]
        temps.append(temp)
        parsed_data.append((row_id, temp))

    if len(temps) < 2:
        pytest.fail("Not enough records in the recovered database to calculate standard deviation.")

    mean_temp = statistics.mean(temps)
    stdev_temp = statistics.stdev(temps)
    result = [
        str(row_id)
        for row_id, temp in parsed_data
        if (temp - mean_temp) / stdev_temp > 3
    ]
    result.sort(key=int)
    return result


def run_triage():
    assert os.path.isfile(TRIAGE_PATH), f"Triage script not found at {TRIAGE_PATH}"
    result = subprocess.run(
        [sys.executable, TRIAGE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"triage.py exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}, stderr: {result.stderr!r}"
    )


def read_anomaly_lines():
    assert os.path.exists(ANOMALIES_PATH), f"Anomalies file not found at {ANOMALIES_PATH}"
    with open(ANOMALIES_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_recovered_database_exists_and_valid():
    assert os.path.exists(DB_PATH), f"Recovered database not found at {DB_PATH}"

    try:
        rows = read_rows(DB_PATH)
    except sqlite3.DatabaseError as e:
        pytest.fail(f"Recovered database is malformed or invalid: {e}")

    assert len(rows) > 0, "Recovered database is empty. Expected it to contain the recovered records."

    expected = expected_original_rows()
    actual = {row_id: payload for row_id, payload in rows}
    assert len(rows) == len(expected), (
        f"Recovered database has {len(rows)} records; expected all {len(expected)} records."
    )
    assert actual == expected, "Recovered database does not contain the original telemetry records."


def test_anomalies_file_correct():
    assert os.path.exists(DB_PATH), "Cannot verify anomalies because recovered database is missing."

    try:
        rows = read_rows(DB_PATH)
    except sqlite3.DatabaseError:
        pytest.fail("Recovered database is malformed, cannot verify anomalies.")

    expected_anomalies = expected_anomalies_from_rows(rows)

    if os.path.exists(ANOMALIES_PATH):
        os.remove(ANOMALIES_PATH)
    run_triage()

    actual_anomalies = read_anomaly_lines()
    assert actual_anomalies == expected_anomalies, (
        f"Anomalies file contents do not match expected. "
        f"Expected: {expected_anomalies}, Got: {actual_anomalies}"
    )


def test_triage_processes_recovered_database_and_latin1_dynamically():
    backup_dir = tempfile.mkdtemp(prefix="telemetry-verifier-")
    saved_anomalies = None
    if os.path.exists(ANOMALIES_PATH):
        with open(ANOMALIES_PATH, "rb") as f:
            saved_anomalies = f.read()

    db_files = [DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm"]
    moved = []

    try:
        for path in db_files:
            if os.path.exists(path):
                destination = os.path.join(backup_dir, os.path.basename(path))
                shutil.move(path, destination)
                moved.append((destination, path))

        base_id = random.SystemRandom().randint(20000, 900000)
        records = []
        for index in range(24):
            temp = 19.0 + (index % 7) * 0.25
            records.append((base_id + index, temp, index % 4 == 0))
        records.append((base_id + 24, 100.0, True))
        random.SystemRandom().shuffle(records)

        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("CREATE TABLE readings (id INTEGER PRIMARY KEY, payload BLOB)")
            for row_id, temp, legacy in records:
                data = {"temp": temp, "status": "legacy" if legacy else "ok"}
                if legacy:
                    data["note"] = "probe\u00b0"
                    payload = json.dumps(data).encode("latin-1")
                else:
                    payload = json.dumps(data).encode("utf-8")
                conn.execute("INSERT INTO readings (id, payload) VALUES (?, ?)", (row_id, payload))
            conn.commit()
        finally:
            conn.close()

        probe_rows = read_rows(DB_PATH)
        expected = expected_anomalies_from_rows(probe_rows)
        if os.path.exists(ANOMALIES_PATH):
            os.remove(ANOMALIES_PATH)

        run_triage()
        actual = read_anomaly_lines()
        assert actual == expected, (
            "triage.py did not compute anomalies from a newly supplied recovered database "
            f"containing UTF-8 and latin-1 payloads. Expected: {expected}, Got: {actual}"
        )
    finally:
        for path in db_files:
            if os.path.exists(path):
                os.remove(path)
        for source, destination in moved:
            shutil.move(source, destination)
        shutil.rmtree(backup_dir, ignore_errors=True)

        if saved_anomalies is None:
            if os.path.exists(ANOMALIES_PATH):
                os.remove(ANOMALIES_PATH)
        else:
            with open(ANOMALIES_PATH, "wb") as f:
                f.write(saved_anomalies)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
