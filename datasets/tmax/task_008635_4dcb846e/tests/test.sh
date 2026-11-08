#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import stat
import subprocess
import time

PIPELINE_SCRIPT = "/home/user/pipeline.sh"
RAW_SENSORS = "/home/user/raw_sensors.csv"
CLEANED_SENSORS = "/home/user/cleaned_sensors.csv"
EXPERIMENTS_LOG = "/home/user/experiments.log"
HEADER = "sensor_id,temp_c,pressure_hpa,vibration_hz"

ORIGINAL_ROWS = [
    "1,25.4,1013.2,50.1",
    "2,28.1,1010.5,45.2",
    "3,150.5,1005.0,10.0",
    "4,-60.0,1100.0,20.0",
    "5,30.0,1008.1,60.5",
    "6,10.2,1020.5,",
    "7,invalid,1015.0,30.0",
    "8,35.5,1001.2,70.2",
    "9,40.1,995.5,80.5",
    "10,22.0,1015.8,40.0",
    "11,26.5,1011.0,55.0",
]
ORIGINAL_VALID = [ORIGINAL_ROWS[i] for i in (0, 1, 4, 7, 8, 9, 10)]

LOG_RE = re.compile(
    r'^\{"timestamp":"([0-9]+)","input_rows":([0-9]+),'
    r'"valid_rows":([0-9]+),"temp_pressure_correlation":(-?[0-9]+\.[0-9]{4})\}$'
)


def correlation(rows):
    values = [(float(row.split(",")[1]), float(row.split(",")[2])) for row in rows]
    n = len(values)
    sx = sum(x for x, _ in values)
    sy = sum(y for _, y in values)
    sxx = sum(x * x for x, _ in values)
    syy = sum(y * y for _, y in values)
    sxy = sum(x * y for x, y in values)
    return (n * sxy - sx * sy) / math.sqrt(
        (n * sxx - sx * sx) * (n * syy - sy * sy)
    )


def write_input(rows):
    with open(RAW_SENSORS, "w", encoding="utf-8", newline="") as f:
        f.write(HEADER + "\n")
        for row in rows:
            f.write(row + "\n")


def run_and_check(rows, expected_valid):
    before = b""
    if os.path.exists(EXPERIMENTS_LOG):
        with open(EXPERIMENTS_LOG, "rb") as f:
            before = f.read()

    started = int(time.time())
    result = subprocess.run([PIPELINE_SCRIPT], capture_output=True, text=True, timeout=20)
    finished = int(time.time())
    assert result.returncode == 0, (
        f"Pipeline script failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    assert os.path.isfile(CLEANED_SENSORS), f"Missing file: {CLEANED_SENSORS}"
    with open(CLEANED_SENSORS, "r", encoding="utf-8") as f:
        actual_lines = f.read().splitlines()
    assert actual_lines == [HEADER] + expected_valid, (
        "cleaned_sensors.csv did not preserve exactly the header and valid input rows.\n"
        f"Expected: {[HEADER] + expected_valid}\nActual: {actual_lines}"
    )

    assert os.path.isfile(EXPERIMENTS_LOG), f"Missing file: {EXPERIMENTS_LOG}"
    with open(EXPERIMENTS_LOG, "rb") as f:
        after = f.read()
    assert after.startswith(before), "experiments.log was overwritten instead of appended to"
    suffix = after[len(before):]
    assert suffix.endswith(b"\n") and suffix.count(b"\n") == 1, (
        "Each execution must append exactly one JSON-formatted line to experiments.log"
    )
    try:
        line = suffix[:-1].decode("utf-8")
    except UnicodeDecodeError as exc:
        raise AssertionError("The appended log line is not UTF-8 text") from exc

    match = LOG_RE.fullmatch(line)
    assert match, f"Log line does not strictly match the required JSON structure: {line!r}"
    entry = json.loads(line)
    assert list(entry.keys()) == [
        "timestamp", "input_rows", "valid_rows", "temp_pressure_correlation"
    ], f"Unexpected JSON keys or key order: {list(entry.keys())}"

    timestamp = int(match.group(1))
    assert started <= timestamp <= finished, (
        f"Timestamp {timestamp} is not the UNIX epoch time of this execution "
        f"({started} through {finished})"
    )
    assert entry["timestamp"] == match.group(1), "timestamp must be a quoted string"
    assert entry["input_rows"] == len(rows), (
        f"Expected input_rows={len(rows)}, got {entry['input_rows']}"
    )
    assert entry["valid_rows"] == len(expected_valid), (
        f"Expected valid_rows={len(expected_valid)}, got {entry['valid_rows']}"
    )

    expected_corr = correlation(expected_valid)
    actual_corr = entry["temp_pressure_correlation"]
    assert isinstance(actual_corr, (int, float)) and not isinstance(actual_corr, bool), (
        f"Correlation must be a JSON number, got {type(actual_corr)}"
    )
    assert math.isclose(actual_corr, expected_corr, abs_tol=0.00005), (
        f"Expected Pearson correlation rounded to {expected_corr:.4f}, got {actual_corr}"
    )
    assert match.group(4) == f"{expected_corr:.4f}", (
        f"Correlation must be rendered to exactly four decimal places; expected "
        f"{expected_corr:.4f}, got {match.group(4)}"
    )
    return entry, actual_lines


def test_pipeline_behavior_and_outputs():
    assert os.path.isfile(PIPELINE_SCRIPT), f"Missing script: {PIPELINE_SCRIPT}"
    mode = os.stat(PIPELINE_SCRIPT).st_mode
    assert bool(mode & stat.S_IXUSR), f"Script is not executable: {PIPELINE_SCRIPT}"
    with open(PIPELINE_SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert re.fullmatch(r"#!(?:/bin/bash|/usr/bin/bash|/usr/bin/env bash)", first_line), (
        "pipeline.sh must be a standalone Bash script with a Bash shebang"
    )

    if os.path.exists(EXPERIMENTS_LOG):
        os.remove(EXPERIMENTS_LOG)

    # Preserve and strengthen all assertions for the original fixture.
    write_input(ORIGINAL_ROWS)
    original_entry, original_output = run_and_check(ORIGINAL_ROWS, ORIGINAL_VALID)
    assert len(original_output) == 8, "Expected one header and seven original data rows"
    assert original_output[0] == HEADER
    assert {line.split(",")[0] for line in original_output[1:]} == {
        "1", "2", "5", "8", "9", "10", "11"
    }
    assert original_entry["input_rows"] == 11
    assert original_entry["valid_rows"] == 7
    assert math.isclose(original_entry["temp_pressure_correlation"], -0.9922, abs_tol=0.0002)

    # Exercise filtering, field preservation, row counting, and correlation on
    # values and IDs selected only when verification runs.
    base = 10000 + secrets.randbelow(800000)
    valid = [
        f"{base},-50.0,800.0,0.0",
        f"{base + 1},150.0,1200.0,5000.0",
        f"-{base + 2},-12.3,1093.7,17.25",
        f"{base + 3},0.0,875.4,222.2",
        f"{base + 4},24.75,1017.9,49.5",
        f"{base + 5},67.2,932.6,1000.0",
        f"{base + 6},100.1,1166.3,4999.9",
        f"{base + 7},42.42,984.8,73.3",
    ]
    invalid = [
        f"bad{base},25.0,1000.0,10.0",
        f"{base + 20}.5,25.0,1000.0,10.0",
        f"{base + 21},150.1,1000.0,10.0",
        f"{base + 22},-50.1,1000.0,10.0",
        f"{base + 23},25x,1000.0,10.0",
        f"{base + 24},25.0,799.9,10.0",
        f"{base + 25},25.0,1200.1,10.0",
        f"{base + 26},25.0,notnum,10.0",
        f"{base + 27},25.0,1000.0,-0.1",
        f"{base + 28},25.0,1000.0,5000.1",
        f"{base + 29},25.0,1000.0,",
        f"{base + 30},,1000.0,10.0",
        f"{base + 31},25.0,1000.0",
        f"{base + 32},25.0,1000.0,10.0,extra",
    ]
    tagged = [(row, True) for row in valid] + [(row, False) for row in invalid]
    secrets.SystemRandom().shuffle(tagged)
    varied_rows = [row for row, _ in tagged]
    varied_valid = [row for row, is_valid in tagged if is_valid]
    write_input(varied_rows)
    run_and_check(varied_rows, varied_valid)


if __name__ == "__main__":
    test_pipeline_behavior_and_outputs()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
