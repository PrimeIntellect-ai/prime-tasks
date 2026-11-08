#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import random
import re
import subprocess
from pathlib import Path

OUTPUT = Path("/home/user/remote_archive/cleaned_data.csv")
SCRIPT = Path("/home/user/pipeline.py")
RAW = Path("/home/user/raw_sensors.log")


def read_csv(path):
    rows = []
    with path.open("r", newline="") as f:
        for row in csv.reader(f):
            if row:
                rows.append(row)
    return rows


def test_cleaned_data_exists():
    """Verify that the cleaned data CSV file was generated in the correct location."""
    file_path = "/home/user/remote_archive/cleaned_data.csv"
    assert os.path.exists(file_path), f"Expected output file not found at {file_path}"
    assert os.path.isfile(file_path), f"Expected {file_path} to be a file, but it is not."


def test_cleaned_data_contents():
    """Verify that the cleaned data CSV contains the correctly processed data."""
    file_path = "/home/user/remote_archive/cleaned_data.csv"
    assert os.path.exists(file_path), f"Cannot verify contents because {file_path} is missing."

    expected_rows = [
        ["timestamp", "sensor_id", "temperature"],
        ["2023-11-01T08:00:00", "sensor_alpha", "20.0"],
        ["2023-11-01T08:00:00", "sensor_beta", "15.5"],
        ["2023-11-01T08:15:00", "sensor_alpha", "22.5"],
        ["2023-11-01T08:15:00", "sensor_beta", "16.0"],
        ["2023-11-01T08:30:00", "sensor_alpha", "25.0"],
        ["2023-11-01T08:30:00", "sensor_beta", "17.0"],
        ["2023-11-01T08:45:00", "sensor_alpha", "24.0"],
        ["2023-11-01T08:45:00", "sensor_beta", "18.0"],
    ]

    actual_rows = read_csv(Path(file_path))
    assert len(actual_rows) == len(expected_rows), (
        f"Row count mismatch. Expected {len(expected_rows)} rows (including header), "
        f"but got {len(actual_rows)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, (
            f"Row {i} mismatch.\nExpected: {expected}\nActual:   {actual}"
        )


def derive_expected(raw_lines):
    pattern = re.compile(
        r"^LOG_START \[([^\]]+)\] - ([^ ]+) reported temp: "
        r"(ERROR|[-+]?(?:\d+(?:\.\d*)?|\.\d+))\n?$"
    )
    seen = set()
    records = []
    for line in raw_lines:
        digest = hashlib.md5(line.encode("utf-8")).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        match = pattern.match(line)
        assert match, f"Verifier generated an invalid fixture line: {line!r}"
        timestamp, sensor_id, value = match.groups()
        records.append({
            "timestamp": timestamp,
            "sensor_id": sensor_id,
            "temperature": None if value == "ERROR" else float(value),
        })

    sensors = {record["sensor_id"] for record in records}
    for sensor in sensors:
        positions = [i for i, record in enumerate(records) if record["sensor_id"] == sensor]
        for group_pos, record_pos in enumerate(positions):
            if records[record_pos]["temperature"] is not None:
                continue
            left = group_pos - 1
            while left >= 0 and records[positions[left]]["temperature"] is None:
                left -= 1
            right = group_pos + 1
            while right < len(positions) and records[positions[right]]["temperature"] is None:
                right += 1
            assert left >= 0 and right < len(positions)
            left_value = records[positions[left]]["temperature"]
            right_value = records[positions[right]]["temperature"]
            fraction = (group_pos - left) / (right - left)
            records[record_pos]["temperature"] = left_value + (right_value - left_value) * fraction

    records.sort(key=lambda record: (record["timestamp"], record["sensor_id"]))
    return [["timestamp", "sensor_id", "temperature"]] + [
        [record["timestamp"], record["sensor_id"], f'{record["temperature"]:.1f}']
        for record in records
    ]


def test_pipeline_executes_and_processes_dynamic_fixture():
    assert SCRIPT.exists(), f"Required pipeline script not found at {SCRIPT}"
    assert SCRIPT.is_file(), f"Expected {SCRIPT} to be a file"

    rng = random.SystemRandom()
    token = f"{rng.getrandbits(64):016x}"
    alpha = f"sensor_alpha_{token}"
    beta = f"sensor_beta_{token}"
    a = rng.randint(30, 70)
    b = rng.randint(5, 25)
    times = [
        "2042-06-10T09:00:00",
        "2042-06-10T09:15:00",
        "2042-06-10T09:30:00",
        "2042-06-10T09:45:00",
    ]

    first = f"LOG_START [{times[0]}] - {alpha} reported temp: {a}.0\n"
    raw_lines = [
        first,
        f"LOG_START [{times[0]}] - {beta} reported temp: {b}.5\n",
        first,
        # Same parsed data but different raw bytes: MD5 deduplication must retain it.
        f"LOG_START [{times[0]}] - {alpha} reported temp: {a}.00\n",
        f"LOG_START [{times[1]}] - {alpha} reported temp: ERROR\n",
        f"LOG_START [{times[1]}] - {beta} reported temp: {b + 1}.5\n",
        f"LOG_START [{times[2]}] - {alpha} reported temp: {a + 4}.0\n",
        f"LOG_START [{times[2]}] - {beta} reported temp: ERROR\n",
        f"LOG_START [{times[3]}] - {alpha} reported temp: {a + 3}.0\n",
        f"LOG_START [{times[3]}] - {beta} reported temp: {b + 5}.5\n",
    ]
    expected = derive_expected(raw_lines)

    old_raw = RAW.read_bytes()
    old_output = OUTPUT.read_bytes() if OUTPUT.exists() and OUTPUT.is_file() else None
    try:
        RAW.write_text("".join(raw_lines), encoding="utf-8")
        if OUTPUT.exists():
            OUTPUT.unlink()
        result = subprocess.run(
            ["python3", str(SCRIPT)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Pipeline exited with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert OUTPUT.exists() and OUTPUT.is_file(), (
            f"Executing {SCRIPT} did not create {OUTPUT}"
        )
        actual = read_csv(OUTPUT)
        assert actual == expected, (
            "Pipeline output for the dynamic fixture was incorrect.\n"
            f"Expected: {expected}\nActual:   {actual}"
        )
    finally:
        RAW.write_bytes(old_raw)
        if old_output is None:
            if OUTPUT.exists() and OUTPUT.is_file():
                OUTPUT.unlink()
        else:
            OUTPUT.parent.mkdir(parents=True, exist_ok=True)
            OUTPUT.write_bytes(old_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
