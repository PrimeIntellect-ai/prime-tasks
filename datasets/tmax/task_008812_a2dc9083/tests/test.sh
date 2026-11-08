#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

LOG_FILE = "/home/user/server_logs.csv"
CSV_OUT = "/home/user/anomalies.csv"
DB_OUT = "/home/user/alerts.db"
SOURCE = "/home/user/detector.c"
EXECUTABLE = "/home/user/detector"


def compute_expected_anomalies(log_file=LOG_FILE):
    assert os.path.isfile(log_file), f"Source file {log_file} is missing."

    windows = {}
    first_ts = None

    with open(log_file, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            ts = int(row[0])
            ip = row[1]

            if first_ts is None:
                first_ts = ts

            # Align the first timestamp down to its containing 10-second boundary.
            base_start = (first_ts // 10) * 10
            window_idx = (ts - base_start) // 10
            window_start = base_start + window_idx * 10

            if window_start not in windows:
                windows[window_start] = {"count": 0, "ips": set()}

            windows[window_start]["count"] += 1
            windows[window_start]["ips"].add(ip)

    if first_ts is None:
        return []

    base_start = (first_ts // 10) * 10
    sorted_starts = sorted(windows)
    if not sorted_starts:
        return []

    max_idx = (sorted_starts[-1] - base_start) // 10
    window_counts = [0] * (max_idx + 1)
    for start in sorted_starts:
        idx = (start - base_start) // 10
        window_counts[idx] = windows[start]["count"]

    expected_rows = []
    for start in sorted_starts:
        idx = (start - base_start) // 10
        if idx >= 5:
            prev_5_sum = sum(window_counts[idx - 5:idx])
            if window_counts[idx] > 3 * (prev_5_sum / 5.0):
                for ip in sorted(windows[start]["ips"]):
                    expected_rows.append((start, ip, window_counts[idx]))

    return expected_rows


def read_csv_output(path):
    rows = []
    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            assert len(row) == 3, f"Invalid row length in {path}: {row}"
            rows.append((int(row[0]), row[1], int(row[2])))
    return rows


def run_detector():
    result = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Detector exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def verify_and_run_program():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} is missing."
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."

    compile_result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE}.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )

    with open(LOG_FILE, "rb") as f:
        original_log = f.read()
    original_db = None
    if os.path.isfile(DB_OUT):
        with open(DB_OUT, "rb") as f:
            original_db = f.read()

    synthetic_rows = []
    normal_ips = ["10.1.0.2", "10.1.0.1"]
    for start in [1000, 1010, 1020, 1030, 1040]:
        synthetic_rows.append([max(1003, start + 3), normal_ips[0], "/x", 200, 10])
        synthetic_rows.append([max(1004, start + 4), normal_ips[1], "/x", 200, 11])
    for i in range(7):
        synthetic_rows.append([1051 + i, "192.0.2.2" if i % 2 else "192.0.2.1", "/x", 200, 12])
    synthetic_rows.sort(key=lambda row: row[0])

    try:
        with open(LOG_FILE, "w", newline="") as f:
            csv.writer(f).writerows(synthetic_rows)
        if os.path.exists(CSV_OUT):
            os.remove(CSV_OUT)
        if os.path.exists(DB_OUT):
            os.remove(DB_OUT)

        run_detector()
        assert os.path.isfile(CSV_OUT), f"{EXECUTABLE} did not create {CSV_OUT}."
        synthetic_actual = sorted(read_csv_output(CSV_OUT), key=lambda x: (x[0], x[1]))
        synthetic_expected = sorted(compute_expected_anomalies(LOG_FILE), key=lambda x: (x[0], x[1]))
        assert synthetic_actual == synthetic_expected, (
            "The compiled C detector failed a boundary-aligned input test."
        )

        with open(LOG_FILE, "wb") as f:
            f.write(original_log)
        if os.path.exists(CSV_OUT):
            os.remove(CSV_OUT)
        if os.path.exists(DB_OUT):
            os.remove(DB_OUT)

        run_detector()
        assert os.path.isfile(CSV_OUT), f"{EXECUTABLE} did not create {CSV_OUT}."
    finally:
        with open(LOG_FILE, "wb") as f:
            f.write(original_log)
        if os.path.exists(DB_OUT):
            os.remove(DB_OUT)
        if original_db is not None:
            with open(DB_OUT, "wb") as f:
                f.write(original_db)


def test_anomalies_csv():
    expected = compute_expected_anomalies()
    assert os.path.isfile(CSV_OUT), f"Output file {CSV_OUT} is missing."

    actual = read_csv_output(CSV_OUT)
    actual_sorted = sorted(actual, key=lambda x: (x[0], x[1]))
    expected_sorted = sorted(expected, key=lambda x: (x[0], x[1]))

    assert actual_sorted == expected_sorted, f"Data in {CSV_OUT} does not match expected anomalies."


def test_alerts_db():
    expected = compute_expected_anomalies()
    assert os.path.isfile(DB_OUT), f"Database file {DB_OUT} is missing."

    conn = sqlite3.connect(DB_OUT)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='anomalies';")
        assert cursor.fetchone() is not None, "Table 'anomalies' does not exist in the database."

        cursor.execute("SELECT window_start, ip, count FROM anomalies ORDER BY window_start ASC, ip ASC;")
        rows = cursor.fetchall()
    finally:
        conn.close()

    actual = [(int(row[0]), row[1], int(row[2])) for row in rows]
    expected_sorted = sorted(expected, key=lambda x: (x[0], x[1]))
    assert actual == expected_sorted, f"Data in {DB_OUT} does not match expected anomalies."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
