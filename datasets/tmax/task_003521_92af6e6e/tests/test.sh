#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import subprocess

A_PATH = '/home/user/sensor_a.csv'
B_PATH = '/home/user/sensor_b.csv'
SOURCE_PATH = '/home/user/drift_analyzer.cpp'
EXECUTABLE_PATH = '/home/user/drift_analyzer'
REPORT_PATH = '/home/user/drift_report.txt'
COMPILED_SOURCE_PATH = '/tmp/drift_analyzer_from_source'


def read_data(path):
    data = []
    with open(path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append((int(row['timestamp']), float(row['temperature'])))
    return data


def compute_expected_report():
    a_data = read_data(A_PATH)
    b_data = read_data(B_PATH)

    min_ts = min(min(x[0] for x in a_data), min(x[0] for x in b_data))
    max_ts = max(max(x[0] for x in a_data), max(x[0] for x in b_data))

    start_time = (min_ts // 600) * 600
    if max_ts % 600 == 0:
        end_time = max_ts
    else:
        end_time = ((max_ts // 600) + 1) * 600

    num_buckets = (end_time - start_time) // 600

    def aggregate(data):
        buckets = [[] for _ in range(num_buckets)]
        for ts, temp in data:
            if start_time <= ts < end_time:
                idx = (ts - start_time) // 600
                buckets[idx].append(temp)

        means = [sum(bucket) / len(bucket) if bucket else None for bucket in buckets]
        first_valid = next((i for i, value in enumerate(means) if value is not None), None)
        if first_valid is not None:
            for i in range(first_valid):
                means[i] = means[first_valid]
            for i in range(first_valid + 1, num_buckets):
                if means[i] is None:
                    means[i] = means[i - 1]
        return means

    agg_a = aggregate(a_data)
    agg_b = aggregate(b_data)

    def z_score(values):
        n = len(values)
        if n == 0:
            return values
        mean = sum(values) / n
        variance = sum((value - mean) ** 2 for value in values) / n
        std_dev = math.sqrt(variance)
        if std_dev == 0:
            return [0.0] * n
        return [(value - mean) / std_dev for value in values]

    norm_a = z_score(agg_a)
    norm_b = z_score(agg_b)
    distance = math.sqrt(sum((a - b) ** 2 for a, b in zip(norm_a, norm_b)))
    return num_buckets, distance


def write_data(path, rows):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'temperature'])
        for timestamp, temperature in rows:
            writer.writerow([timestamp, format(temperature, '.10f')])


def check_report(expected_buckets, expected_distance):
    assert os.path.exists(REPORT_PATH), f"Output file {REPORT_PATH} is missing."
    with open(REPORT_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {REPORT_PATH}, found {len(lines)}."
    assert lines[0] == f"Total Buckets: {expected_buckets}", \
        f"Line 1 mismatch. Expected 'Total Buckets: {expected_buckets}', got '{lines[0]}'."
    expected_distance_line = f"Euclidean Distance: {expected_distance:.4f}"
    assert lines[1] == expected_distance_line, \
        f"Line 2 mismatch. Expected '{expected_distance_line}', got '{lines[1]}'."


def run_and_check(executable):
    expected_buckets, expected_distance = compute_expected_report()
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [executable], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, \
        f"{executable} exited with status {result.returncode}. stderr: {result.stderr}"
    check_report(expected_buckets, expected_distance)


def make_cases():
    rng = secrets.SystemRandom()
    cases = []
    for case_number, bucket_count in enumerate((9, 14, 21)):
        base = rng.randrange(2500000, 3500000) * 600
        a_rows = []
        b_rows = []

        for i in range(bucket_count):
            if i == 0 or i == bucket_count - 1 or (i + case_number) % 4 != 1:
                a_value = 8.0 + 0.37 * i + math.sin(i * 0.73) * 3.2 + rng.uniform(-0.2, 0.2)
                a_rows.append((base + i * 600 + 23 + (i * 41) % 480, a_value))
                if i % 3 == 0:
                    a_rows.append((base + i * 600 + 511, a_value + rng.uniform(-0.7, 0.7)))

            # This deliberately creates leading and interior gaps for sensor B.
            if i >= 2 and (i + 2 * case_number) % 5 != 2:
                b_value = 10.0 - 0.16 * i + math.cos(i * 0.49) * 2.6 + 0.08 * i * i + rng.uniform(-0.2, 0.2)
                b_rows.append((base + i * 600 + 67 + (i * 29) % 420, b_value))
                if i % 4 == 1:
                    b_rows.append((base + i * 600 + 557, b_value + rng.uniform(-0.6, 0.6)))

        # Ensure B has data near the end while preserving its leading gaps.
        if not any(ts // 600 == base // 600 + bucket_count - 1 for ts, _ in b_rows):
            i = bucket_count - 1
            b_rows.append((base + i * 600 + 401, 11.3 + 0.11 * i + rng.uniform(-0.2, 0.2)))
        cases.append((a_rows, b_rows))
    return cases


def test_submission():
    assert os.path.exists(SOURCE_PATH), "Source file drift_analyzer.cpp is missing."
    assert os.path.exists(EXECUTABLE_PATH), "Compiled executable drift_analyzer is missing."
    assert os.access(EXECUTABLE_PATH, os.X_OK), "drift_analyzer is not executable."
    assert os.path.isfile(SOURCE_PATH), "drift_analyzer.cpp is not a regular file."
    assert os.path.isfile(EXECUTABLE_PATH), "drift_analyzer is not a regular file."
    with open(EXECUTABLE_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "drift_analyzer is not a compiled ELF executable."

    with open(A_PATH, 'rb') as f:
        original_a = f.read()
    with open(B_PATH, 'rb') as f:
        original_b = f.read()

    try:
        # The submitted executable must produce the report from the original inputs.
        run_and_check(EXECUTABLE_PATH)

        # Compile the submitted C++ source independently so dummy source cannot pass.
        compile_result = subprocess.run(
            ['g++', '-std=c++17', '-O2', SOURCE_PATH, '-o', COMPILED_SOURCE_PATH],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_result.returncode == 0, \
            f"drift_analyzer.cpp failed to compile with g++: {compile_result.stderr}"

        # Exercise both the submitted binary and a fresh build of its source on
        # unpredictable inputs, including aggregation and leading/interior gaps.
        for a_rows, b_rows in make_cases():
            for executable in (EXECUTABLE_PATH, COMPILED_SOURCE_PATH):
                write_data(A_PATH, a_rows)
                write_data(B_PATH, b_rows)
                run_and_check(executable)
    finally:
        with open(A_PATH, 'wb') as f:
            f.write(original_a)
        with open(B_PATH, 'wb') as f:
            f.write(original_b)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
