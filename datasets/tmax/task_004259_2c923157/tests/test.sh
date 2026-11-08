#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import shutil
import stat
import subprocess

SOURCE = "/home/user/etl.go"
CSV_PATH = "/home/user/data/sensors.csv"
OUTPUT_DIR = "/home/user/etl_output"
METRICS_DIR = "/home/user/metrics"
BINARY = "/tmp/etl_submission"

ORIGINAL_CSV = """timestamp,sensor_id,temperature,pressure
2023-10-01T00:00,1,20.5,101.3
2023-10-01T01:00,2,22.1,101.5
2023-10-01T02:00,1,21.0,101.4
2023-10-01T03:00,3,19.8,101.1
2023-10-01T04:00,A,20.0,101.2
2023-10-01T05:00,1,,101.2
2023-10-01T06:00,2,25.0,bad
2023-10-01T07:00,3,23.5,101.7
2023-10-01T08:00,4,21.0,101.3
"""


def reset_outputs():
    shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
    shutil.rmtree(METRICS_DIR, ignore_errors=True)


def run_binary():
    result = subprocess.run(
        [BINARY], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"ETL executable failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_lines(path):
    assert os.path.isfile(path), f"Partition file {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def pearson(records):
    xs = [r[2] for r in records]
    ys = [r[3] for r in records]
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    numerator = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    denominator = math.sqrt(
        sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys)
    )
    return numerator / denominator


def validate_complete_output(expected):
    expected_by_sensor = {1: [], 2: [], 3: []}
    for row in expected:
        expected_by_sensor[row[1]].append(row)

    for sensor_id in (1, 2, 3):
        path = f"{OUTPUT_DIR}/sensor_{sensor_id}/valid.jsonl"
        lines = read_lines(path)
        assert len(lines) == len(expected_by_sensor[sensor_id]), (
            f"Expected {len(expected_by_sensor[sensor_id])} lines in {path}, got {len(lines)}."
        )
        actual = []
        for line in lines:
            obj = json.loads(line)
            assert set(obj) == {"timestamp", "sensor_id", "temperature", "pressure"}
            assert isinstance(obj["timestamp"], str)
            assert isinstance(obj["sensor_id"], int) and not isinstance(obj["sensor_id"], bool)
            assert isinstance(obj["temperature"], (int, float)) and not isinstance(obj["temperature"], bool)
            assert isinstance(obj["pressure"], (int, float)) and not isinstance(obj["pressure"], bool)
            assert obj["sensor_id"] == sensor_id
            actual.append((obj["timestamp"], obj["sensor_id"], float(obj["temperature"]), float(obj["pressure"])))
        assert sorted(actual) == sorted(expected_by_sensor[sensor_id]), (
            f"Incorrect records in sensor {sensor_id} partition: {actual!r}"
        )

    metrics_file = f"{METRICS_DIR}/correlation.txt"
    assert os.path.isfile(metrics_file), f"Metrics file {metrics_file} does not exist."
    with open(metrics_file, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert re.fullmatch(r"-?\d+\.\d{4}", content), (
        f"Correlation must be written with exactly four decimal places, got {content!r}."
    )
    expected_correlation = format(pearson(expected), ".4f")
    assert content == expected_correlation, (
        f"Expected correlation {expected_correlation!r}, got {content!r}."
    )


def check_original_assertions():
    metrics_file = "/home/user/metrics/correlation.txt"
    assert os.path.isfile(metrics_file), f"Metrics file {metrics_file} does not exist."
    with open(metrics_file, "r") as f:
        content = f.read().strip()
    assert content == "0.9923", f"Expected correlation to be '0.9923', but got '{content}'."

    file_path = "/home/user/etl_output/sensor_1/valid.jsonl"
    lines = read_lines(file_path)
    assert len(lines) == 2, f"Expected 2 lines in {file_path}, got {len(lines)}."
    parsed_lines = [json.loads(line) for line in lines]
    for obj in parsed_lines:
        assert "timestamp" in obj and isinstance(obj["timestamp"], str), "Missing or invalid 'timestamp'."
        assert "sensor_id" in obj and isinstance(obj["sensor_id"], int), "Missing or invalid 'sensor_id'."
        assert "temperature" in obj and isinstance(obj["temperature"], float), "Missing or invalid 'temperature'."
        assert "pressure" in obj and isinstance(obj["pressure"], float), "Missing or invalid 'pressure'."
        assert obj["sensor_id"] == 1, "Incorrect sensor_id in partition 1."
    temperatures = {obj["temperature"] for obj in parsed_lines}
    assert 20.5 in temperatures, "Expected temperature 20.5 not found in sensor 1 partition."
    assert 21.0 in temperatures, "Expected temperature 21.0 not found in sensor 1 partition."

    file_path = "/home/user/etl_output/sensor_2/valid.jsonl"
    lines = read_lines(file_path)
    assert len(lines) == 1, f"Expected 1 line in {file_path}, got {len(lines)}."
    obj = json.loads(lines[0])
    assert obj["sensor_id"] == 2, "Incorrect sensor_id in partition 2."
    assert obj["temperature"] == 22.1, "Expected temperature 22.1 not found in sensor 2 partition."
    assert obj["pressure"] == 101.5, "Expected pressure 101.5 not found in sensor 2 partition."

    file_path = "/home/user/etl_output/sensor_3/valid.jsonl"
    lines = read_lines(file_path)
    assert len(lines) == 2, f"Expected 2 lines in {file_path}, got {len(lines)}."
    parsed_lines = [json.loads(line) for line in lines]
    for obj in parsed_lines:
        assert obj["sensor_id"] == 3, "Incorrect sensor_id in partition 3."
    temperatures = {obj["temperature"] for obj in parsed_lines}
    assert 19.8 in temperatures, "Expected temperature 19.8 not found in sensor 3 partition."
    assert 23.5 in temperatures, "Expected temperature 23.5 not found in sensor 3 partition."


def write_random_case(case_number):
    rng = random.SystemRandom()
    slope = rng.choice([-1.37, -0.83, 0.91, 1.46])
    valid = []
    for i, sensor_id in enumerate((1, 2, 3, 1, 3, 2, 1, 2, 3)):
        temperature = float(f"{rng.uniform(8.0, 38.0) + i * 0.017:.6f}")
        pressure = float(f"{115.0 + slope * temperature + rng.uniform(-2.5, 2.5):.6f}")
        timestamp = f"secret-{case_number}-{rng.randrange(10**8, 10**9)}-{i}"
        valid.append((timestamp, sensor_id, temperature, pressure))

    rows = [["timestamp", "sensor_id", "temperature", "pressure"]]
    rows.extend([[t, str(s), repr(temp), repr(pressure)] for t, s, temp, pressure in valid])
    rows.extend([
        ["", "1", "12.25", "98.75"],
        ["bad-id-low", "0", "17.5", "100.1"],
        ["bad-id-high", "4", "18.5", "100.2"],
        ["bad-id-text", "A", "19.5", "100.3"],
        ["bad-temperature", "2", "not-a-float", "100.4"],
        ["bad-pressure", "3", "20.5", "not-a-float"],
        ["missing-column", "1", "21.5"],
        ["too", "many", "columns", "in", "this-row"],
    ])
    rng.shuffle(rows[1:])
    os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        csv.writer(f).writerows(rows)
    return valid


def main():
    assert os.path.exists(SOURCE), f"Required Go source {SOURCE} does not exist."
    assert not os.path.islink(SOURCE), f"Required Go source {SOURCE} must be a regular file, not a symlink."
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"Required Go source {SOURCE} is not a regular file."

    build = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert build.returncode == 0, (
        f"Could not compile {SOURCE}.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    with open(CSV_PATH, "w", encoding="utf-8") as f:
        f.write(ORIGINAL_CSV)
    reset_outputs()
    run_binary()
    check_original_assertions()
    original_expected = [
        ("2023-10-01T00:00", 1, 20.5, 101.3),
        ("2023-10-01T01:00", 2, 22.1, 101.5),
        ("2023-10-01T02:00", 1, 21.0, 101.4),
        ("2023-10-01T03:00", 3, 19.8, 101.1),
        ("2023-10-01T07:00", 3, 23.5, 101.7),
    ]
    validate_complete_output(original_expected)

    for case_number in (1, 2):
        expected = write_random_case(case_number)
        reset_outputs()
        run_binary()
        validate_complete_output(expected)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
