#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import subprocess

CSV_PATH = '/home/user/system_metrics.csv'
LOG_PATH = '/home/user/anomalies.log'
CPP_PATH = '/home/user/detector.cpp'
BIN_PATH = '/tmp/detector_under_test'


def compute_expected_anomalies(csv_path):
    if not os.path.isfile(csv_path):
        return []

    buckets = {}
    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = int(row['timestamp'])
            cpu = float(row['cpu'])
            mem = float(row['mem'])
            net_in = float(row['net_in'])
            net_out = float(row['net_out'])

            bucket_idx = ts // 60
            if bucket_idx not in buckets:
                buckets[bucket_idx] = {'cpu': [], 'mem': [], 'net_in': [], 'net_out': []}

            buckets[bucket_idx]['cpu'].append(cpu)
            buckets[bucket_idx]['mem'].append(mem)
            buckets[bucket_idx]['net_in'].append(net_in)
            buckets[bucket_idx]['net_out'].append(net_out)

    sorted_indices = sorted(buckets.keys())
    anomalies = []
    prev_norm = None

    for idx in sorted_indices:
        b = buckets[idx]
        avg_cpu = sum(b['cpu']) / len(b['cpu'])
        avg_mem = sum(b['mem']) / len(b['mem'])
        avg_net_in = sum(b['net_in']) / len(b['net_in'])
        avg_net_out = sum(b['net_out']) / len(b['net_out'])

        norm = (
            avg_cpu / 100.0,
            avg_mem / 16000.0,
            avg_net_in / 1000.0,
            avg_net_out / 1000.0
        )

        if prev_norm is not None:
            dist = math.sqrt(sum((norm[i] - prev_norm[i]) ** 2 for i in range(4)))
            if dist > 0.4:
                anomalies.append(
                    f"[LOG] Anomaly detected at bucket {idx * 60}: distance={dist:.4f}"
                )

        prev_norm = norm

    return anomalies


def read_log():
    assert os.path.isfile(LOG_PATH), f"Output log file {LOG_PATH} was not generated."
    with open(LOG_PATH, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_anomalies_log_exists_and_correct():
    assert os.path.isfile(CSV_PATH), f"Input CSV file {CSV_PATH} is missing."
    assert os.path.isfile(LOG_PATH), f"Output log file {LOG_PATH} was not generated."

    expected_lines = compute_expected_anomalies(CSV_PATH)
    actual_lines = read_log()

    assert actual_lines == expected_lines, (
        f"Contents of {LOG_PATH} do not match expected anomalies.\n"
        f"Expected: {expected_lines}\n"
        f"Actual:   {actual_lines}"
    )


def test_cpp_source_exists():
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} is missing."


def make_generated_rows(rng):
    base = rng.randint(20000, 90000)
    low_cpu = rng.uniform(14.0, 24.0)
    low_mem = rng.uniform(3200.0, 5200.0)
    low_in = rng.uniform(90.0, 180.0)
    low_out = rng.uniform(40.0, 100.0)
    high_cpu = rng.uniform(84.0, 96.0)
    high_in = rng.uniform(760.0, 920.0)

    # Gaps deliberately exercise comparison of consecutive non-empty buckets.
    means = [
        (base,     low_cpu,       low_mem,         low_in,        low_out),
        (base + 1, low_cpu + 2.0, low_mem + 120.0, low_in + 12.0, low_out + 8.0),
        (base + 4, high_cpu,      low_mem + 180.0, high_in,       low_out + 10.0),
        (base + 5, high_cpu - 1.5,low_mem + 220.0, high_in - 15.0,low_out + 14.0),
        (base + 9, low_cpu + 1.0, low_mem + 40.0,  low_in + 5.0,  low_out + 2.0),
    ]

    rows = []
    for idx, cpu, mem, net_in, net_out in means:
        # Symmetric samples ensure that implementations must aggregate each bucket.
        rows.append((idx * 60 + 7,  cpu - 2.5, mem - 90.0, net_in - 11.0, net_out - 6.0))
        rows.append((idx * 60 + 43, cpu + 2.5, mem + 90.0, net_in + 11.0, net_out + 6.0))
    return rows


def write_rows(rows):
    with open(CSV_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'cpu', 'mem', 'net_in', 'net_out'])
        writer.writerows(rows)


def execute_and_check():
    expected = compute_expected_anomalies(CSV_PATH)
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    result = subprocess.run(
        [BIN_PATH], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled detector exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    actual = read_log()
    assert actual == expected, (
        "Compiled detector produced an incorrect log.\n"
        f"Expected: {expected}\nActual:   {actual}"
    )


def test_cpp_compiles_and_detector_processes_inputs():
    with open(CSV_PATH, 'rb') as f:
        original_csv = f.read()
    with open(LOG_PATH, 'rb') as f:
        original_log = f.read()

    try:
        compile_result = subprocess.run(
            ['g++', '-std=c++17', '-O2', CPP_PATH, '-o', BIN_PATH],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert compile_result.returncode == 0, (
            "detector.cpp did not compile successfully.\n"
            f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
        )
        assert os.path.isfile(BIN_PATH), "Compilation did not produce an executable."

        # Re-run the submitted program on the supplied input.
        execute_and_check()

        # Exercise the compiled artifact on unpredictable inputs and derive each answer.
        rng = random.SystemRandom()
        for _ in range(3):
            write_rows(make_generated_rows(rng))
            assert compute_expected_anomalies(CSV_PATH), "Generated case should contain anomalies."
            execute_and_check()
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        with open(LOG_PATH, 'wb') as f:
            f.write(original_log)
        if os.path.exists(BIN_PATH):
            os.remove(BIN_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
