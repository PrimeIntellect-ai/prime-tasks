#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess

SOURCE = "/home/user/app/processor.c"
EXECUTABLE = "/home/user/app/processor"
INPUT = "/home/user/data/metrics.csv"
OUTPUT = "/home/user/data/output.csv"
HEADER = "bucket_ts,bucket_avg,moving_avg"


def expected_lines(input_path):
    buckets = []
    current_bucket = None
    current_sum = 0.0
    current_count = 0
    previous_ts = None

    with open(input_path, newline="") as f:
        reader = csv.reader(f)
        assert next(reader, None) == ["timestamp", "value"], "Input CSV header is incorrect"
        for row in reader:
            assert len(row) == 2, "Malformed input row"
            ts = int(row[0])
            value = float(row[1])

            if previous_ts is not None and ts == previous_ts:
                continue
            previous_ts = ts

            bucket = ts - (ts % 10)
            if current_bucket is None:
                current_bucket = bucket
            elif bucket != current_bucket:
                buckets.append((current_bucket, current_sum / current_count))
                current_bucket = bucket
                current_sum = 0.0
                current_count = 0

            current_sum += value
            current_count += 1

    if current_bucket is not None:
        buckets.append((current_bucket, current_sum / current_count))

    result = [HEADER]
    recent = []
    for bucket, average in buckets:
        recent.append(average)
        recent = recent[-3:]
        moving = sum(recent) / len(recent)
        result.append(f"{bucket},{average:.4f},{moving:.4f}")
    return result


def actual_lines(output_path):
    with open(output_path) as f:
        return [line.strip() for line in f if line.strip()]


def assert_output_matches(input_path, output_path):
    expected = expected_lines(input_path)
    actual = actual_lines(output_path)
    assert actual, "Output CSV is empty"
    assert actual[0] == HEADER, "Output CSV header is incorrect"
    assert len(actual) == len(expected), (
        f"Output CSV has {len(actual)} lines, expected {len(expected)}"
    )
    for i, (out_line, exp_line) in enumerate(zip(actual, expected), 1):
        assert out_line == exp_line, (
            f"Mismatch at line {i}: expected '{exp_line}', got '{out_line}'"
        )


def test_c_source_exists():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} does not exist"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable"


def test_output_csv_exists():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist"


def test_existing_output_is_correct():
    assert_output_matches(INPUT, OUTPUT)


def test_source_compiles_and_processes_fresh_input():
    seed = int.from_bytes(os.urandom(8), "big")
    rng = random.Random(seed)
    rows = []
    ts = 1700000000

    for i in range(2500):
        if i and i % 97 == 0:
            ts += rng.randint(21, 55)
        else:
            ts += rng.randint(1, 4)

        value_text = f"{rng.randint(-500000, 500000) / 1000.0:.6f}"
        rows.append((ts, value_text))

        if rng.random() < 0.45:
            duplicate_text = f"{rng.randint(-900000, 900000) / 1000.0:.6f}"
            rows.append((ts, duplicate_text))
            if rng.random() < 0.2:
                rows.append((ts, f"{rng.randint(-900000, 900000) / 1000.0:.6f}"))

    with open(INPUT, "w", newline="") as f:
        f.write("timestamp,value\n")
        for row_ts, row_value in rows:
            f.write(f"{row_ts},{row_value}\n")

    if os.path.lexists(EXECUTABLE):
        os.remove(EXECUTABLE)
    compile_result = subprocess.run(
        ["gcc", "-O3", SOURCE, "-o", EXECUTABLE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run_result = subprocess.run(
        [EXECUTABLE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert run_result.returncode == 0, f"Processor failed:\n{run_result.stderr}"
    assert os.path.isfile(OUTPUT), "Processor did not create output.csv"
    assert_output_matches(INPUT, OUTPUT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
