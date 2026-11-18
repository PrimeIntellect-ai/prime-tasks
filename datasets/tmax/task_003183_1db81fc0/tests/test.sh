#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import random
import re
import subprocess

INPUT_FILE = "/home/user/sensor_data.csv"
OUTPUT_FILE = "/home/user/processed_stats.csv"
SOURCE_FILE = "/home/user/processor.c"
EXECUTABLE = "/home/user/processor"
EXPECTED_HEADER = "bucket_time,centroid_distance,rolling_avg_distance"


def test_processed_stats_exists():
    output_file = "/home/user/processed_stats.csv"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist. Did the C program run successfully?"


def test_processed_stats_content():
    input_file = "/home/user/sensor_data.csv"
    output_file = "/home/user/processed_stats.csv"

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."

    # Recompute the expected output from the input file
    buckets = {}
    with open(input_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            ts = int(parts[0])
            x = float(parts[1])
            y = float(parts[2])

            bucket = (ts // 10) * 10
            if bucket not in buckets:
                buckets[bucket] = {'x': [], 'y': []}
            buckets[bucket]['x'].append(x)
            buckets[bucket]['y'].append(y)

    sorted_buckets = sorted(buckets.keys())
    distances = []
    expected_rows = []

    for b in sorted_buckets:
        mean_x = sum(buckets[b]['x']) / len(buckets[b]['x'])
        mean_y = sum(buckets[b]['y']) / len(buckets[b]['y'])
        dist = math.sqrt(mean_x**2 + mean_y**2)
        distances.append(dist)

        window = distances[-3:]
        rolling_avg = sum(window) / len(window)

        expected_rows.append(f"{b},{dist:.2f},{rolling_avg:.2f}")

    # Read the actual output
    with open(output_file, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) > 0, "Output file is empty."

    expected_header = "bucket_time,centroid_distance,rolling_avg_distance"
    assert actual_lines[0] == expected_header, f"Header mismatch. Expected '{expected_header}', got '{actual_lines[0]}'."

    actual_rows = actual_lines[1:]
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but found {len(actual_rows)}."

    for i, (expected, actual) in enumerate(zip(expected_rows, actual_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected '{expected}', got '{actual}'."


def expected_output(rows):
    buckets = {}
    for ts, x, y, _signal in rows:
        bucket = (ts // 10) * 10
        values = buckets.setdefault(bucket, [[], []])
        values[0].append(x)
        values[1].append(y)

    distances = []
    lines = [EXPECTED_HEADER]
    for bucket in sorted(buckets):
        xs, ys = buckets[bucket]
        mean_x = sum(xs) / len(xs)
        mean_y = sum(ys) / len(ys)
        distance = math.sqrt(mean_x ** 2 + mean_y ** 2)
        distances.append(distance)
        rolling = sum(distances[-3:]) / len(distances[-3:])
        lines.append(f"{bucket},{distance:.2f},{rolling:.2f}")
    return lines


def run_and_check(program, rows):
    with open(INPUT_FILE, "w") as f:
        for ts, x, y, signal in rows:
            f.write(f"{ts},{x},{y},{signal}\n")

    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    result = subprocess.run(
        [program], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_FILE), f"{program} did not generate {OUTPUT_FILE}."

    with open(OUTPUT_FILE, "r") as f:
        actual = [line.rstrip("\r\n") for line in f if line.strip()]
    expected = expected_output(rows)
    assert actual == expected, (
        f"{program} produced incorrect output for verifier-generated input. "
        f"Expected {expected!r}, got {actual!r}."
    )
    for line in actual[1:]:
        assert re.fullmatch(r"-?\d+,-?\d+\.\d{2},-?\d+\.\d{2}", line), (
            f"Output row is not formatted to exactly two decimal places: {line!r}"
        )


def test_c_source_and_executable_generate_results():
    assert os.path.isfile(SOURCE_FILE), f"Required C source {SOURCE_FILE} is missing."
    assert os.path.getsize(SOURCE_FILE) > 0, f"Required C source {SOURCE_FILE} is empty."
    assert os.path.isfile(EXECUTABLE), f"Required executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."

    rebuilt = "/tmp/processor_rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE_FILE, "-lm", "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        f"processor.c does not compile successfully: {compile_result.stderr}"
    )

    with open(INPUT_FILE, "rb") as f:
        original_input = f.read()
    with open(OUTPUT_FILE, "rb") as f:
        original_output = f.read()

    try:
        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        cases = []
        for _ in range(2):
            base = rng.randrange(200, 2000) * 10
            bucket = base
            rows = []
            for _bucket_index in range(rng.randint(5, 8)):
                bucket += rng.randint(1, 4) * 10
                offsets = sorted(rng.sample(range(10), rng.randint(1, 4)))
                for offset in offsets:
                    x = rng.randint(-160, 160) / 4.0
                    y = rng.randint(-160, 160) / 4.0
                    signal = rng.randint(-100, 100) / 2.0
                    rows.append((bucket + offset, x, y, signal))
            rows.sort(key=lambda row: row[0])
            cases.append(rows)

        # Exercise both the required /home/user/processor artifact and a fresh
        # compilation of the submitted C source on verifier-generated data.
        for rows in cases:
            run_and_check(EXECUTABLE, rows)
            run_and_check(rebuilt, rows)
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)
        with open(OUTPUT_FILE, "wb") as f:
            f.write(original_output)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
