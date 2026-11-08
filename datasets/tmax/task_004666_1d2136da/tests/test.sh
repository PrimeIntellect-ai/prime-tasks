#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess
from collections import defaultdict

HOME = "/home/user"
SOURCE = f"{HOME}/process_sensors.cpp"
BINARY = f"{HOME}/process_sensors"
RAW = f"{HOME}/raw_sensors.csv"
OUTPUT = f"{HOME}/aggregated_sensors.csv"
LOG = f"{HOME}/pipeline.log"
HEADER = ["bucket_start_ts", "sensor_id", "avg_temp", "avg_humidity"]

INITIAL_FIXTURE = """timestamp_ms,sensor_id,temperature,humidity
1600000000000,A,20.0,50.0
1600000300000,A,22.0,52.0
1600000600000,A,,54.0
1600000900000,A,26.0,56.0
1600001200000,A,105.0,60.0
1600001500000,A,28.0,58.0
1600000000000,B,10.0,40.0
1600000500000,B,-60.0,42.0
1600000800000,B,14.0,44.0
1600001000000,B,16.0,
1600001600000,B,18.0,48.0
"""


def derive_expected(fixture):
    parsed = []
    warnings = []
    reader = csv.DictReader(fixture.splitlines())
    assert reader.fieldnames == ["timestamp_ms", "sensor_id", "temperature", "humidity"]

    for row in reader:
        ts = int(row["timestamp_ms"])
        temp = None if row["temperature"] == "" else float(row["temperature"])
        humidity = None if row["humidity"] == "" else float(row["humidity"])
        if temp is not None and (temp > 100.0 or temp < -50.0):
            warnings.append(
                f"[WARN] Dropped row with timestamp {ts} due to out-of-bounds temperature."
            )
            continue
        parsed.append({"ts": ts, "sensor": row["sensor_id"], "temp": temp, "humidity": humidity})

    by_sensor = defaultdict(list)
    for row in parsed:
        by_sensor[row["sensor"]].append(row)

    for rows in by_sensor.values():
        rows.sort(key=lambda r: r["ts"])
        for metric in ("temp", "humidity"):
            for i, row in enumerate(rows):
                if row[metric] is not None:
                    continue
                before = next(rows[j] for j in range(i - 1, -1, -1) if rows[j][metric] is not None)
                after = next(rows[j] for j in range(i + 1, len(rows)) if rows[j][metric] is not None)
                row[metric] = before[metric] + (after[metric] - before[metric]) * (
                    (row["ts"] - before["ts"]) / (after["ts"] - before["ts"])
                )

    groups = defaultdict(lambda: [0.0, 0.0, 0])
    for rows in by_sensor.values():
        for row in rows:
            bucket = (row["ts"] // 900000) * 900000
            group = groups[(bucket, row["sensor"])]
            group[0] += row["temp"]
            group[1] += row["humidity"]
            group[2] += 1

    expected_rows = []
    for (bucket, sensor), (temp_sum, humidity_sum, count) in sorted(groups.items()):
        expected_rows.append([
            str(bucket),
            sensor,
            f"{temp_sum / count:.2f}",
            f"{humidity_sum / count:.2f}",
        ])
    return expected_rows, warnings


def verify_outputs(fixture, required_initial_warnings=None):
    expected_rows, expected_warnings = derive_expected(fixture)

    assert os.path.isfile(OUTPUT), "Aggregated CSV output is missing."
    with open(OUTPUT, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, "Aggregated CSV is empty."
    assert rows[0] == HEADER, f"Expected header {HEADER}, but got {rows[0]}"
    assert len(rows[1:]) == len(expected_rows), (
        f"Expected {len(expected_rows)} data rows, got {len(rows[1:])}"
    )
    for i, expected in enumerate(expected_rows):
        assert rows[i + 1] == expected, (
            f"Row {i + 1} mismatch. Expected {expected}, got {rows[i + 1]}"
        )

    assert os.path.isfile(LOG), "Pipeline log file is missing."
    with open(LOG) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) >= len(expected_warnings) + 1, "Pipeline log is missing required messages."
    for warning in expected_warnings:
        assert warning in lines, f"Expected warning '{warning}' not found in log."
    if required_initial_warnings:
        for warning in required_initial_warnings:
            assert warning in lines, f"Expected warning '{warning}' not found in log."
    assert lines[-1] == "[INFO] Pipeline finished.", (
        "The last line of the log must be the finished info message."
    )


def run_case(executable, fixture, required_initial_warnings=None):
    with open(RAW, "w") as f:
        f.write(fixture)
    for path in (OUTPUT, LOG):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run([executable], cwd=HOME, text=True, capture_output=True, timeout=15)
    assert result.returncode == 0, (
        f"{executable} failed with code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    verify_outputs(fixture, required_initial_warnings)


def make_dynamic_fixture():
    anchor = ((1700000000000 + secrets.randbelow(5000000000)) // 900000) * 900000
    q = 18 + 2 * secrets.randbelow(8)
    h = 40 + 2 * secrets.randbelow(8)
    p = 8 + 2 * secrets.randbelow(8)
    g = 25 + 2 * secrets.randbelow(8)
    high = 101 + secrets.randbelow(20)
    low = -51 - secrets.randbelow(20)

    rows = [
        (anchor + 150000, "Z9", p, g),
        (anchor + 500000, "Z9", "", ""),
        (anchor + 800000, "Z9", p + 13, g + 26),
        (anchor + 950000, "Z9", low, g + 28),
        (anchor + 1200000, "Z9", p + 16, g + 30),
        (anchor + 1650000, "Z9", p + 20, g + 34),
        (anchor + 100000, "AA", q, h),
        (anchor + 400000, "AA", "", h + 2),
        (anchor + 700000, "AA", q + 4, h + 4),
        (anchor + 1000000, "AA", high, h + 7),
        (anchor + 1300000, "AA", q + 8, ""),
        (anchor + 1700000, "AA", q + 12, h + 14),
    ]
    lines = ["timestamp_ms,sensor_id,temperature,humidity"]
    lines.extend(",".join(map(str, row)) for row in rows)
    return "\n".join(lines) + "\n"


def test_complete_pipeline():
    assert os.path.isfile(SOURCE), "C++ source file is missing."
    assert os.path.isfile(BINARY), "Compiled binary is missing."
    assert os.path.isfile(OUTPUT), "Aggregated CSV output is missing."
    assert os.path.isfile(LOG), "Pipeline log file is missing."
    assert os.access(BINARY, os.X_OK), "Compiled binary is not executable."
    assert stat.S_ISREG(os.stat(BINARY).st_mode), "Compiled binary is not a regular file."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled binary is not an ELF executable."

    rebuilt = "/tmp/process_sensors_rebuilt"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", rebuilt],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"C++ source did not compile with C++17. stderr={compile_result.stderr!r}"
    )

    initial_warnings = [
        "[WARN] Dropped row with timestamp 1600001200000 due to out-of-bounds temperature.",
        "[WARN] Dropped row with timestamp 1600000500000 due to out-of-bounds temperature.",
    ]
    run_case(BINARY, INITIAL_FIXTURE, initial_warnings)
    run_case(BINARY, make_dynamic_fixture())
    run_case(rebuilt, make_dynamic_fixture())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
