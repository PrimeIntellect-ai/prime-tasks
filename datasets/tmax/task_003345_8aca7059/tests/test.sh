#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import random
import secrets
import subprocess
from collections import defaultdict

SOURCE_PATH = "/home/user/etl_processor.cpp"
RAW_PATH = "/home/user/raw_telemetry.csv"
OUT_PATH = "/home/user/summary_stats.csv"
EXECUTABLE_PATH = "/tmp/etl_processor_verified"


def compile_processor():
    result = subprocess.run(
        ["g++", "-O3", "-std=c++17", "-o", EXECUTABLE_PATH, SOURCE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"C++ source failed to compile:\n{result.stderr}"
    assert os.path.isfile(EXECUTABLE_PATH), "Compilation did not produce an executable"


def run_processor():
    if os.path.exists(OUT_PATH):
        os.remove(OUT_PATH)
    result = subprocess.run(
        [EXECUTABLE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"ETL processor exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def expected_from_file(path):
    stats = defaultdict(list)
    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) != 3:
                continue
            sensor_id, ts_str, temp_str = row
            try:
                timestamp = int(ts_str)
                temp = float(temp_str)
            except ValueError:
                continue
            if not sensor_id.startswith("SN-"):
                continue
            if timestamp <= 0:
                continue
            if not (-50.0 <= temp <= 150.0):
                continue
            stats[sensor_id].append(temp)

    expected = ["sensor_id,count,min_temp,max_temp,avg_temp"]
    for sensor_id in sorted(stats):
        temps = stats[sensor_id]
        expected.append(
            f"{sensor_id},{len(temps)},{min(temps):.2f},"
            f"{max(temps):.2f},{sum(temps) / len(temps):.2f}"
        )
    return expected


def read_actual_output():
    assert os.path.isfile(OUT_PATH), f"Output file missing: {OUT_PATH}"
    with open(OUT_PATH, "r") as f:
        return f.read().strip().splitlines()


def test_cpp_source_exists():
    source_path = "/home/user/etl_processor.cpp"
    assert os.path.isfile(source_path), f"C++ source file missing: {source_path}"


def test_summary_stats_correctness():
    raw_path = "/home/user/raw_telemetry.csv"
    out_path = "/home/user/summary_stats.csv"

    assert os.path.isfile(raw_path), f"Raw telemetry missing: {raw_path}"

    compile_processor()
    run_processor()

    assert os.path.isfile(out_path), f"Output file missing: {out_path}"

    # Compute expected results from the input data
    stats = defaultdict(list)
    with open(raw_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) != 3:
                continue
            sensor_id, ts_str, temp_str = row

            # Validation Constraints
            if not sensor_id.startswith("SN-"):
                continue
            if int(ts_str) <= 0:
                continue
            temp = float(temp_str)
            if not (-50.0 <= temp <= 150.0):
                continue

            stats[sensor_id].append(temp)

    expected_rows = [["sensor_id", "count", "min_temp", "max_temp", "avg_temp"]]
    for sensor_id in sorted(stats.keys()):
        temps = stats[sensor_id]
        count = len(temps)
        min_temp = min(temps)
        max_temp = max(temps)
        avg_temp = sum(temps) / count
        expected_rows.append([
            sensor_id,
            str(count),
            f"{min_temp:.2f}",
            f"{max_temp:.2f}",
            f"{avg_temp:.2f}"
        ])

    expected_content = [",".join(row) for row in expected_rows]

    # Read actual results
    with open(out_path, "r") as f:
        actual_content = f.read().strip().splitlines()

    assert len(actual_content) == len(expected_content), (
        f"Row count mismatch. Expected {len(expected_content)} rows (including header), "
        f"but got {len(actual_content)}."
    )

    for i, (actual_row, expected_row) in enumerate(zip(actual_content, expected_content)):
        assert actual_row.strip() == expected_row, (
            f"Mismatch at row {i+1}.\n"
            f"Expected: {expected_row}\n"
            f"Actual:   {actual_row.strip()}"
        )


def test_processor_on_unseen_input():
    token = secrets.token_hex(8).upper()
    ids = [
        f"SN-{token}-Z",
        f"SN-{token}-A",
        f"SN-{token}-M",
        f"SN-{token}-B",
    ]

    rows = []
    valid_values = {
        ids[0]: [-50.0, 50.0, 150.0],
        ids[1]: [1.0, 2.0, 3.0, 4.0],
        ids[2]: [-20.0, -10.0, 0.0],
        ids[3]: [99.25],
    }
    timestamp = secrets.randbelow(1_000_000_000) + 1
    for sensor_id, temperatures in valid_values.items():
        for temperature in temperatures:
            rows.append([sensor_id, str(timestamp), str(temperature)])
            timestamp += secrets.randbelow(1000) + 1

    # Rows violating each validation constraint must not affect the result.
    rows.extend([
        [f"XX-{token}", str(timestamp), "25.0"],
        [f"XSN-{token}", str(timestamp + 1), "26.0"],
        [f"SN-{token}-BADTIME", "0", "27.0"],
        [f"SN-{token}-BADTIME", "-17", "28.0"],
        [f"SN-{token}-COLD", str(timestamp + 2), "-50.01"],
        [f"SN-{token}-HOT", str(timestamp + 3), "150.01"],
    ])
    random.SystemRandom().shuffle(rows)

    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()
    original_output = None
    if os.path.exists(OUT_PATH):
        with open(OUT_PATH, "rb") as f:
            original_output = f.read()

    try:
        with open(RAW_PATH, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerows(rows)

        expected_content = expected_from_file(RAW_PATH)
        run_processor()
        actual_content = read_actual_output()

        assert len(actual_content) == len(expected_content), (
            f"Unseen-input row count mismatch: expected {len(expected_content)}, "
            f"got {len(actual_content)}"
        )
        for i, (actual_row, expected_row) in enumerate(zip(actual_content, expected_content)):
            assert actual_row.strip() == expected_row, (
                f"Unseen-input mismatch at row {i+1}.\n"
                f"Expected: {expected_row}\nActual:   {actual_row.strip()}"
            )
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        if original_output is None:
            if os.path.exists(OUT_PATH):
                os.remove(OUT_PATH)
        else:
            with open(OUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
