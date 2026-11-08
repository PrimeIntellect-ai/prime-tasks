#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import stat
import subprocess
from datetime import datetime, timedelta

import pytest

OUTPUT_FILE = "/home/user/cleaned_sensor_stats.csv"
RAW_FILE = "/home/user/raw_sensor_data.csv"
VENV_PYTHON = "/home/user/venv/bin/python"

CANONICAL_RAW = """sensor_id,timestamp,temperature
S1,2023-10-01 10:00:00,20.0
S1,2023-10-01 11:00:00,21.0
S1,2023-10-01 11:00:00,99.9
S1,2023-10-01 14:00:00,24.0
S1,2023-10-01 19:00:00,30.0
S2,2023-10-01 08:00:00,10.0
S2,2023-10-01 09:00:00,12.0
S2,2023-10-01 10:00:00,14.0
S2,2023-10-01 10:00:00,14.0
S2,2023-10-01 14:00:00,22.0
"""


def read_csv_data(filepath):
    assert os.path.exists(filepath), f"Output file {filepath} not found."
    with open(filepath, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        rows = list(reader)
    return header, rows


def parse_float(val):
    val = val.strip()
    if not val:
        return None
    return float(val)


def expected_from_raw(raw_text):
    source = list(csv.DictReader(raw_text.splitlines()))
    first = {}
    for row in source:
        key = (row["sensor_id"], datetime.strptime(row["timestamp"], "%Y-%m-%d %H:%M:%S"))
        if key not in first:
            first[key] = float(row["temperature"])

    result = []
    sensors = sorted({sensor for sensor, _ in first})
    for sensor in sensors:
        observed = {ts: value for (sid, ts), value in first.items() if sid == sensor}
        start, end = min(observed), max(observed)
        times = []
        current = start
        while current <= end:
            times.append(current)
            current += timedelta(hours=1)
        values = [observed.get(ts) for ts in times]

        i = 0
        while i < len(values):
            if values[i] is not None:
                i += 1
                continue
            gap_start = i
            while i < len(values) and values[i] is None:
                i += 1
            gap_len = i - gap_start
            if gap_start > 0 and i < len(values) and gap_len <= 3:
                left = values[gap_start - 1]
                right = values[i]
                step = (right - left) / (gap_len + 1)
                for offset in range(gap_len):
                    values[gap_start + offset] = left + step * (offset + 1)

        for index, ts in enumerate(times):
            window = [v for v in values[max(0, index - 3):index + 1] if v is not None]
            rolling = sum(window) / len(window) if len(window) >= 2 else None
            result.append([
                sensor,
                ts.strftime("%Y-%m-%d %H:%M:%S"),
                "" if values[index] is None else f"{values[index]:.2f}",
                "" if rolling is None else f"{rolling:.2f}",
            ])
    return result


def script_candidates():
    preferred = "/home/user/process_sensors.py"
    found = []
    if os.path.isfile(preferred) and not os.path.islink(preferred):
        found.append(preferred)
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "venv" and not d.startswith(".")]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".py") and path != preferred and not os.path.islink(path):
                try:
                    if stat.S_ISREG(os.stat(path).st_mode):
                        found.append(path)
                except OSError:
                    pass
    return found


def run_script(script, raw_text):
    with open(RAW_FILE, "w", newline="") as f:
        f.write(raw_text)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    completed = subprocess.run(
        [VENV_PYTHON, script],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"Pipeline script failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.exists(OUTPUT_FILE), "Pipeline script did not generate the required output file."


assert os.path.isfile(VENV_PYTHON) and os.access(VENV_PYTHON, os.X_OK), \
    "The required virtual environment /home/user/venv is missing or invalid."
CANDIDATES = script_candidates()
assert CANDIDATES, "No Python pipeline script was found under /home/user."
SCRIPT = CANDIDATES[0]
run_script(SCRIPT, CANONICAL_RAW)


def test_output_file_exists_and_header():
    """Test that the output file exists and has the correct header."""
    header, _ = read_csv_data(OUTPUT_FILE)
    expected_header = ["sensor_id", "timestamp", "temperature", "rolling_avg_temp"]
    assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}"


def test_output_row_count():
    """Test that the output file has exactly 17 data rows."""
    _, rows = read_csv_data(OUTPUT_FILE)
    assert len(rows) == 17, f"Row count mismatch. Expected 17, got {len(rows)}"


def test_output_sorting_and_format():
    """Test that the data is sorted by sensor_id and timestamp, and timestamp is formatted correctly."""
    _, rows = read_csv_data(OUTPUT_FILE)
    prev_sensor = None
    prev_time = None
    for row in rows:
        assert len(row) == 4, f"Row has incorrect number of columns: {row}"
        sensor_id, ts_str, _, _ = row
        try:
            ts = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            pytest.fail(f"Timestamp format incorrect: {ts_str}")
        if prev_sensor is not None:
            if sensor_id == prev_sensor:
                assert ts > prev_time, f"Timestamps not sorted ascending for sensor {sensor_id}: {prev_time} -> {ts}"
            else:
                assert sensor_id > prev_sensor, f"Sensor IDs not sorted ascending: {prev_sensor} -> {sensor_id}"
        prev_sensor = sensor_id
        prev_time = ts


def test_s1_imputation_and_rolling_avg_at_14():
    """Validate specific values for S1 at 14:00 (interpolated and rolling avg)."""
    _, rows = read_csv_data(OUTPUT_FILE)
    s1_14_row = next((row for row in rows if row[0] == "S1" and row[1] == "2023-10-01 14:00:00"), None)
    assert s1_14_row is not None, "Row for S1 at 14:00 not found."
    temp = parse_float(s1_14_row[2])
    rolling = parse_float(s1_14_row[3])
    assert temp is not None and math.isclose(temp, 24.0, abs_tol=0.01), f"Imputation error S1 14:00. Expected 24.0, got {temp}"
    assert rolling is not None and math.isclose(rolling, 22.5, abs_tol=0.01), f"Rolling avg error S1 14:00. Expected 22.5, got {rolling}"


def test_s1_missing_gaps_limit_at_15():
    """Validate missing gaps limit (S1 at 15:00 should be NaN, but rolling avg should exist)."""
    _, rows = read_csv_data(OUTPUT_FILE)
    s1_15_row = next((row for row in rows if row[0] == "S1" and row[1] == "2023-10-01 15:00:00"), None)
    assert s1_15_row is not None, "Row for S1 at 15:00 not found."
    temp = parse_float(s1_15_row[2])
    rolling = parse_float(s1_15_row[3])
    assert temp is None, f"Interpolation limit not respected for S1 15:00. Expected empty/NaN, got {temp}"
    assert rolling is not None and math.isclose(rolling, 23.0, abs_tol=0.01), f"Rolling avg error over NaNs S1 15:00. Expected 23.0, got {rolling}"


def test_s2_values():
    """Validate a specific row for S2 to ensure correct processing of another group."""
    _, rows = read_csv_data(OUTPUT_FILE)
    s2_14_row = next((row for row in rows if row[0] == "S2" and row[1] == "2023-10-01 14:00:00"), None)
    assert s2_14_row is not None, "Row for S2 at 14:00 not found."
    temp = parse_float(s2_14_row[2])
    rolling = parse_float(s2_14_row[3])
    assert temp is not None and math.isclose(temp, 22.0, abs_tol=0.01), f"Temperature error S2 14:00. Expected 22.0, got {temp}"
    assert rolling is not None and math.isclose(rolling, 19.0, abs_tol=0.01), f"Rolling avg error S2 14:00. Expected 19.0, got {rolling}"


def test_all_canonical_rows_and_exact_formatting():
    header, rows = read_csv_data(OUTPUT_FILE)
    assert header == ["sensor_id", "timestamp", "temperature", "rolling_avg_temp"]
    expected = expected_from_raw(CANONICAL_RAW)
    assert rows == expected, f"Complete canonical output mismatch.\nExpected: {expected}\nGot: {rows}"


def test_z_pipeline_on_unseen_input():
    base = 100 + secrets.randbelow(500)
    dynamic_raw = f"""sensor_id,timestamp,temperature
B,2024-02-03 02:00:00,{base + 10}.0
A,2024-02-03 00:00:00,{base + 1}.0
A,2024-02-03 00:00:00,{base + 999}.0
B,2024-02-03 03:00:00,{base + 14}.0
B,2024-02-03 03:00:00,{base + 888}.0
A,2024-02-03 03:00:00,{base + 7}.0
A,2024-02-03 08:00:00,{base + 17}.0
B,2024-02-03 07:00:00,{base + 22}.0
C,2024-02-03 05:00:00,{base + 30}.0
"""
    run_script(SCRIPT, dynamic_raw)
    header, rows = read_csv_data(OUTPUT_FILE)
    assert header == ["sensor_id", "timestamp", "temperature", "rolling_avg_temp"]
    expected = expected_from_raw(dynamic_raw)
    assert rows == expected, f"Pipeline failed on unseen input.\nExpected: {expected}\nGot: {rows}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
