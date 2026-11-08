#!/bin/bash
mkdir -p /logs/verifier

BACKUP_LOG=$(mktemp)
HAD_LOG=0
if [ -e /home/user/server.log ]; then
    cp -L /home/user/server.log "$BACKUP_LOG" 2>/dev/null && HAD_LOG=1
fi
restore_log() {
    rm -f /home/user/server.log
    if [ "$HAD_LOG" = "1" ]; then
        cp "$BACKUP_LOG" /home/user/server.log
        chmod 777 /home/user/server.log 2>/dev/null || true
    fi
    rm -f "$BACKUP_LOG"
}
trap restore_log EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import subprocess
from collections import defaultdict

LOG_FILE_PATH = "/home/user/server.log"
C_SOURCE_PATH = "/home/user/analyze_logs.c"
EXECUTABLE_PATH = "/home/user/analyze_logs"
SUMMARY_CSV_PATH = "/home/user/summary.csv"
REBUILT_PATH = "/tmp/analyze_logs_rebuilt"
HEADER = ["hour_bucket", "endpoint", "count", "avg_duration", "max_duration"]


def expected_from_lines(lines):
    aggregations = defaultdict(lambda: {"count": 0, "total_duration": 0, "max_duration": -1})
    for line in lines:
        line = line.strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(" | ")]
        if len(parts) != 5:
            continue
        timestamp, ip, level, duration_str, endpoint = parts
        if level not in ("INFO", "WARN", "ERROR"):
            continue
        try:
            duration = int(duration_str)
        except ValueError:
            continue
        if duration <= 0 or not endpoint.startswith("/api/"):
            continue
        key = (timestamp[:13], endpoint)
        aggregations[key]["count"] += 1
        aggregations[key]["total_duration"] += duration
        aggregations[key]["max_duration"] = max(aggregations[key]["max_duration"], duration)

    rows = []
    for (hour_bucket, endpoint), stats in aggregations.items():
        rows.append({
            "hour_bucket": hour_bucket,
            "endpoint": endpoint,
            "count": str(stats["count"]),
            "avg_duration": str(math.floor(stats["total_duration"] / stats["count"])),
            "max_duration": str(stats["max_duration"]),
        })
    rows.sort(key=lambda row: (row["hour_bucket"], row["endpoint"]))
    return rows


def read_summary():
    assert os.path.exists(SUMMARY_CSV_PATH), f"Summary CSV missing at {SUMMARY_CSV_PATH}"
    assert os.path.isfile(SUMMARY_CSV_PATH), f"{SUMMARY_CSV_PATH} is not a file"
    with open(SUMMARY_CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == HEADER, f"CSV header is incorrect. Got: {reader.fieldnames}"
        return list(reader)


def assert_summary(lines):
    expected_rows = expected_from_lines(lines)
    actual_rows = read_summary()
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows in CSV, but got {len(actual_rows)}"
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i + 1} mismatch.\nExpected: {expected}\nActual: {actual}"


def run_case(binary, lines):
    if os.path.lexists(LOG_FILE_PATH):
        os.unlink(LOG_FILE_PATH)
    with open(LOG_FILE_PATH, "w") as f:
        f.write("\n".join(lines) + "\n")
    if os.path.lexists(SUMMARY_CSV_PATH):
        os.unlink(SUMMARY_CSV_PATH)
    result = subprocess.run(
        [binary], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=8
    )
    assert result.returncode == 0, (
        f"{binary} exited with {result.returncode}.\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert_summary(lines)


def generated_lines(tag):
    a = secrets.randbelow(700) + 31
    b = secrets.randbelow(700) + 32
    c = secrets.randbelow(700) + 33
    d = secrets.randbelow(700) + 34
    ep_a = f"/api/a_{tag}_{secrets.token_hex(4)}"
    ep_z = f"/api/z_{tag}_{secrets.token_hex(4)}"
    return [
        f"2041-07-03T19:55:01Z | 10.2.0.1 | WARN | {a} | {ep_z}",
        f"2038-01-11T02:01:02Z | 10.2.0.2 | INFO | {b} | {ep_a}",
        f"2041-07-03T19:03:03Z | 10.2.0.3 | ERROR | {c} | {ep_z}",
        f"2041-07-03T19:04:04Z | 10.2.0.4 | INFO | {d} | {ep_a}",
        f"2038-01-11T02:05:05Z | 10.2.0.5 | ERROR | {a + b} | {ep_a}",
        f"2041-07-03T20:06:06Z | 10.2.0.6 | INFO | {c + d} | /api/data/v2",
        f"2041-07-03T19:07:07Z | 10.2.0.7 | DEBUG | 99999 | {ep_z}",
        f"2041-07-03T19:08:08Z | 10.2.0.8 | TRACE | 88888 | {ep_a}",
        f"2041-07-03T19:09:09Z | 10.2.0.9 | INFO | 0 | {ep_a}",
        f"2041-07-03T19:10:10Z | 10.2.0.10 | WARN | -17 | {ep_z}",
        f"2041-07-03T19:11:11Z | 10.2.0.11 | ERROR | nope | {ep_z}",
        "2041-07-03T19:12:12Z | 10.2.0.12 | INFO | 500 | /health",
        "2041-07-03T19:13:13Z | 10.2.0.13 | INFO | 500 | /api",
        f"2041-07-03T19:14:14Z | 10.2.0.14 | info | 500 | {ep_a}",
        "malformed log entry",
        "",
    ]


def test_c_source_exists():
    assert os.path.exists(C_SOURCE_PATH), f"C source file missing at {C_SOURCE_PATH}"
    assert os.path.isfile(C_SOURCE_PATH), f"{C_SOURCE_PATH} is not a file"


def test_executable_exists():
    assert os.path.exists(EXECUTABLE_PATH), f"Compiled executable missing at {EXECUTABLE_PATH}"
    assert os.path.isfile(EXECUTABLE_PATH), f"{EXECUTABLE_PATH} is not a file"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not a compiled ELF executable"


def test_summary_csv_exists():
    assert os.path.exists(SUMMARY_CSV_PATH), f"Summary CSV missing at {SUMMARY_CSV_PATH}"
    assert os.path.isfile(SUMMARY_CSV_PATH), f"{SUMMARY_CSV_PATH} is not a file"


def test_summary_csv_content():
    assert os.path.exists(LOG_FILE_PATH), f"Log file missing at {LOG_FILE_PATH}"
    with open(LOG_FILE_PATH, "r") as f:
        lines = f.readlines()
    assert_summary(lines)


def test_source_compiles():
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_SOURCE_PATH, "-o", REBUILT_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, f"C source failed to compile:\n{result.stderr}"
    assert os.path.isfile(REBUILT_PATH) and os.access(REBUILT_PATH, os.X_OK)
    with open(REBUILT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF"


def test_submitted_executable_processes_fresh_input():
    run_case(EXECUTABLE_PATH, generated_lines("submitted"))


def test_rebuilt_source_processes_different_fresh_input():
    run_case(REBUILT_PATH, generated_lines("rebuilt"))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
