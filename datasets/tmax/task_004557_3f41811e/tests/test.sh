#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import shutil
import sqlite3
import struct
import subprocess
from datetime import datetime, timedelta, timezone

import pandas as pd
import pytest

VERIFY = "/home/user/verify_stream.py"
PIPELINE = "/home/user/pipeline.py"
DB = "/home/user/metrics.db"
INTEGRATION = "/var/opt/integration_test"


def run_sanitizer(path):
    return subprocess.run(
        ["python3", VERIFY, "--input", str(path)],
        capture_output=True,
        timeout=10,
    )


def write_csv(path, rows, encoding="utf-8"):
    with open(path, "w", encoding=encoding, newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "sensor_id", "temperature"])
        writer.writerows(rows)


def test_verify_stream_exists():
    assert os.path.exists(VERIFY), "verify_stream.py is missing"
    assert os.path.isfile(VERIFY), "verify_stream.py is not a regular file"


def test_original_adversarial_corpus():
    clean_dir = "/var/opt/corpus/clean"
    evil_dir = "/var/opt/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)] if os.path.exists(clean_dir) else []
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)] if os.path.exists(evil_dir) else []

    clean_failures = [os.path.basename(f) for f in clean_files if run_sanitizer(f).returncode != 0]
    evil_failures = [os.path.basename(f) for f in evil_files if run_sanitizer(f).returncode == 0]

    errors = []
    if clean_failures:
        errors.append(f"clean files rejected: {', '.join(clean_failures)}")
    if evil_failures:
        errors.append(f"evil files accepted: {', '.join(evil_failures)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_sanitizer_generated_corpus(tmp_path):
    token = secrets.token_hex(6)
    clean_cases = [
        (
            "utf8",
            [
                ["2000-01-01T00:00:00Z", f"A{token}", "-100.0"],
                ["2050-12-31T23:59:59+00:00", f"B{token}", "200"],
                ["2027-06-15T12:30:45.125-04:00", f"C{token}9", "21.375"],
            ],
            "utf-8",
        ),
        (
            "utf16",
            [["2031-03-04T05:06:07Z", f"D{token}", "0.0"]],
            "utf-16",
        ),
        (
            "cp1252",
            [["2040-11-12T13:14:15", f"E{token}", "-0.25"]],
            "cp1252",
        ),
    ]

    for label, rows, encoding in clean_cases:
        path = tmp_path / f"{secrets.token_hex(8)}_{label}.csv"
        write_csv(path, rows, encoding)
        result = run_sanitizer(path)
        assert result.returncode == 0, f"valid {label} CSV was rejected: {result.stderr!r}"

    evil_rows = [
        [["1999-12-31T23:59:59Z", f"S{token}", "10"]],
        [["2051-01-01T00:00:00Z", f"S{token}", "10"]],
        [["2023-02-29T00:00:00Z", f"S{token}", "10"]],
        [["not-a-date", f"S{token}", "10"]],
        [["2025-01-01T00:00:00Z", f"bad_{token}", "10"]],
        [["2025-01-01T00:00:00Z", f"x{token};DROP", "10"]],
        [["2025-01-01T00:00:00Z", "", "10"]],
        [["2025-01-01T00:00:00Z", f"S{token}", "-100.001"]],
        [["2025-01-01T00:00:00Z", f"S{token}", "200.001"]],
        [["2025-01-01T00:00:00Z", f"S{token}", "nan"]],
        [["2025-01-01T00:00:00Z", f"S{token}", "inf"]],
        [["2025-01-01T00:00:00Z", f"S{token}", "not-a-float"]],
    ]

    for rows in evil_rows:
        path = tmp_path / f"{secrets.token_hex(10)}.csv"
        write_csv(path, rows)
        result = run_sanitizer(path)
        assert result.returncode == 1, f"invalid CSV was accepted: {rows!r}"

    malformed = tmp_path / f"{secrets.token_hex(10)}.csv"
    malformed.write_bytes(
        b"timestamp,sensor_id,temperature\n"
        b"2025-01-01T00:00:00Z,sensor\x81bad,20\n"
    )
    assert run_sanitizer(malformed).returncode == 1, "corrupt/invalidly encoded input was accepted"

    mixed = tmp_path / f"{secrets.token_hex(10)}.csv"
    write_csv(mixed, [
        ["2025-01-01T00:00:00Z", f"OK{token}", "25"],
        ["2025-01-01T00:01:00Z", f"bad-{token}", "25"],
        ["2025-01-01T00:02:00Z", f"OK{token}", "26"],
    ])
    assert run_sanitizer(mixed).returncode == 1, "a file containing one invalid row was accepted"


def binary_record(timestamp, sensor_id, temperature):
    ts = timestamp.encode("ascii")
    sid = sensor_id.encode("ascii")
    assert len(ts) < 24 and len(sid) < 16
    return struct.pack("<24s16sd", ts + b"\0", sid + b"\0", float(temperature))


def normalized_time(value):
    parsed = pd.to_datetime(str(value), utc=True, errors="raise")
    return parsed.to_pydatetime()


def test_pipeline_execution_and_db():
    assert os.path.exists(PIPELINE), "pipeline.py is missing"
    assert os.path.isfile(PIPELINE), "pipeline.py is not a regular file"

    os.makedirs(INTEGRATION, exist_ok=True)
    for name in os.listdir(INTEGRATION):
        path = os.path.join(INTEGRATION, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    if os.path.exists(DB):
        os.unlink(DB)

    suffix = secrets.token_hex(3).upper()
    sensor_a = "A" + suffix
    sensor_b = "B" + suffix
    bad_sensor = "BAD-" + suffix
    base = datetime(2028, 1, 1, 3, 0, 0, tzinfo=timezone.utc) + timedelta(days=secrets.randbelow(300))
    temps = [float(secrets.randbelow(41) + 5) for _ in range(6)]

    def iso(minutes):
        return (base + timedelta(minutes=minutes)).isoformat().replace("+00:00", "Z")

    csv_path = os.path.join(INTEGRATION, secrets.token_hex(5) + ".csv")
    write_csv(csv_path, [
        [iso(0), sensor_a, temps[0]],
        [iso(4), bad_sensor, 199.0],
        [iso(2), sensor_b, temps[3]],
        [iso(3), sensor_a, 999.0],
    ], encoding="utf-16")

    parquet_path = os.path.join(INTEGRATION, secrets.token_hex(5) + ".parquet")
    pd.DataFrame([
        {"timestamp": iso(9), "sensor_id": sensor_a, "temperature": temps[1]},
        {"timestamp": iso(7), "sensor_id": sensor_b, "temperature": temps[4]},
        {"timestamp": "invalid-date", "sensor_id": sensor_a, "temperature": 17.0},
        {"timestamp": iso(8), "sensor_id": "BAD SPACE", "temperature": 18.0},
    ]).to_parquet(parquet_path, index=False)

    dat_path = os.path.join(INTEGRATION, secrets.token_hex(5) + ".dat")
    with open(dat_path, "wb") as f:
        f.write(binary_record(iso(20), sensor_a, temps[2]))
        f.write(binary_record(iso(16), sensor_b, temps[5]))
        f.write(binary_record(iso(12), bad_sensor, 22.0))
        f.write(binary_record(iso(13), sensor_a, -150.0))

    result = subprocess.run(
        ["python3", PIPELINE],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"pipeline execution failed: stdout={result.stdout!r} stderr={result.stderr!r}"
    assert os.path.exists(DB), f"Database {DB} was not created."

    conn = sqlite3.connect(DB)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='rolling_temps';")
        assert cursor.fetchone() is not None, "Table 'rolling_temps' does not exist in the database."

        cursor.execute("PRAGMA table_info(rolling_temps);")
        columns = {row[1] for row in cursor.fetchall()}
        expected_columns = {"sensor_id", "window_end_time", "avg_temperature"}
        assert expected_columns.issubset(columns), f"Table 'rolling_temps' is missing required columns. Found: {columns}"

        cursor.execute("SELECT sensor_id, window_end_time, avg_temperature FROM rolling_temps")
        actual_rows = cursor.fetchall()
    finally:
        conn.close()

    expected = [
        (sensor_a, base + timedelta(minutes=0), temps[0]),
        (sensor_a, base + timedelta(minutes=9), (temps[0] + temps[1]) / 2.0),
        (sensor_a, base + timedelta(minutes=20), (temps[1] + temps[2]) / 2.0),
        (sensor_b, base + timedelta(minutes=2), temps[3]),
        (sensor_b, base + timedelta(minutes=7), (temps[3] + temps[4]) / 2.0),
        (sensor_b, base + timedelta(minutes=16), (temps[3] + temps[4] + temps[5]) / 3.0),
    ]

    assert len(actual_rows) == len(expected), f"expected exactly {len(expected)} valid aggregate rows, got {actual_rows!r}"
    actual = {}
    for sensor_id, window_end, average in actual_rows:
        assert sensor_id in {sensor_a, sensor_b}, f"invalid/unexpected sensor was exported: {sensor_id!r}"
        key = (sensor_id, normalized_time(window_end))
        assert key not in actual, f"duplicate aggregate row for {key!r}"
        actual[key] = float(average)

    for sensor_id, window_end, average in expected:
        key = (sensor_id, window_end)
        assert key in actual, f"missing aggregate row for {key!r}; got {actual!r}"
        assert math.isclose(actual[key], average, rel_tol=1e-9, abs_tol=1e-9), (
            f"wrong rolling average for {key!r}: expected {average}, got {actual[key]}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
