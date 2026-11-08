#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import math


def read_nonempty(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_prepare_data_script_runs():
    script_path = "/home/user/scripts/prepare_data.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"

    with open(script_path, "r") as f:
        script_text = f.read()
    assert re.search(r"\bawk\b", script_text), "prepare_data.sh must use awk for CSV parsing and floating-point math"

    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"prepare_data.sh failed to run. Stderr: {result.stderr}"

    assert os.path.isfile("/home/user/data/train_raw.csv"), "train_raw.csv was not created"
    assert os.path.isfile("/home/user/data/test_raw.csv"), "test_raw.csv was not created"
    assert os.path.isfile("/home/user/data/train_scaled.csv"), "train_scaled.csv was not created"
    assert os.path.isfile("/home/user/data/test_scaled.csv"), "test_scaled.csv was not created"

    raw_lines = read_nonempty("/home/user/data/raw.csv")
    assert read_nonempty("/home/user/data/train_raw.csv") == raw_lines[:80], "train_raw.csv must contain the first 80 raw.csv rows in order"
    assert read_nonempty("/home/user/data/test_raw.csv") == raw_lines[80:], "test_raw.csv must contain the last 20 raw.csv rows in order"


def test_scaled_data_correctness():
    raw_csv = "/home/user/data/raw.csv"
    train_scaled_csv = "/home/user/data/train_scaled.csv"
    test_scaled_csv = "/home/user/data/test_scaled.csv"

    with open(raw_csv, "r") as f:
        raw_data = [line.strip().split(",") for line in f if line.strip()]

    assert len(raw_data) == 100, "raw.csv should have exactly 100 lines"

    train_raw = raw_data[:80]
    test_raw = raw_data[80:]

    # Calculate population mean and std on train data only
    sum1 = sum(float(row[0]) for row in train_raw)
    sum2 = sum(float(row[1]) for row in train_raw)
    mean1 = sum1 / 80.0
    mean2 = sum2 / 80.0

    sumsq1 = sum((float(row[0]) - mean1)**2 for row in train_raw)
    sumsq2 = sum((float(row[1]) - mean2)**2 for row in train_raw)
    std1 = math.sqrt(sumsq1 / 80.0)
    std2 = math.sqrt(sumsq2 / 80.0)

    def check_scaled_file(filepath, raw_subset):
        with open(filepath, "r") as f:
            scaled_data = [line.strip().split(",") for line in f if line.strip()]

        assert len(scaled_data) == len(raw_subset), f"{filepath} has incorrect number of rows"

        for i, (scaled_row, raw_row) in enumerate(zip(scaled_data, raw_subset)):
            assert len(scaled_row) == 3, f"Row {i+1} in {filepath} must have exactly three columns"
            expected_x1 = (float(raw_row[0]) - mean1) / std1
            expected_x2 = (float(raw_row[1]) - mean2) / std2
            expected_y = raw_row[2]

            assert abs(float(scaled_row[0]) - expected_x1) < 1e-4, f"Row {i+1} in {filepath} X1 is incorrect. Expected {expected_x1}, got {scaled_row[0]}"
            assert abs(float(scaled_row[1]) - expected_x2) < 1e-4, f"Row {i+1} in {filepath} X2 is incorrect. Expected {expected_x2}, got {scaled_row[1]}"
            assert scaled_row[2] == expected_y, f"Row {i+1} in {filepath} y is incorrect. Expected {expected_y}, got {scaled_row[2]}"

    check_scaled_file(train_scaled_csv, train_raw)
    check_scaled_file(test_scaled_csv, test_raw)


def test_bootstrap_script_runs():
    script_path = "/home/user/scripts/bootstrap.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"

    with open(script_path, "r") as f:
        script_text = f.read()
    assert re.search(r"\bRANDOM\b", script_text), "bootstrap.sh must use Bash's RANDOM variable"

    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"bootstrap.sh failed to run. Stderr: {result.stderr}"

    for i in range(1, 6):
        boot_file = f"/home/user/data/boot_{i}.csv"
        assert os.path.isfile(boot_file), f"{boot_file} was not created"


def test_bootstrap_files_correctness():
    train_scaled_csv = "/home/user/data/train_scaled.csv"
    with open(train_scaled_csv, "r") as f:
        train_lines = set(line.strip() for line in f if line.strip())

    for i in range(1, 6):
        boot_file = f"/home/user/data/boot_{i}.csv"
        with open(boot_file, "r") as f:
            boot_data = [line.strip() for line in f if line.strip()]

        assert len(boot_data) == 80, f"{boot_file} should have exactly 80 rows, got {len(boot_data)}"

        for j, line in enumerate(boot_data):
            assert line in train_lines, f"Line {j+1} in {boot_file} is not from train_scaled.csv: {line}"


def test_bootstrap_is_genuine_sampling_with_replacement():
    """Exercise bootstrap.sh on 80 distinguishable rows to expose constant-row or shuffle implementations."""
    train_path = "/home/user/data/train_scaled.csv"
    script_path = "/home/user/scripts/bootstrap.sh"
    with open(train_path, "rb") as f:
        original = f.read()

    probe_rows = [f"{1000+i}.125,{2000+i}.375,{i % 2}" for i in range(80)]
    probe_set = set(probe_rows)

    try:
        with open(train_path, "w") as f:
            f.write("\n".join(probe_rows) + "\n")

        for i in range(1, 6):
            try:
                os.remove(f"/home/user/data/boot_{i}.csv")
            except FileNotFoundError:
                pass

        result = subprocess.run(["bash", script_path], capture_output=True, text=True)
        assert result.returncode == 0, f"bootstrap.sh failed on a valid 80-row training file. Stderr: {result.stderr}"

        samples = []
        for i in range(1, 6):
            boot_file = f"/home/user/data/boot_{i}.csv"
            assert os.path.isfile(boot_file), f"{boot_file} was not created"
            rows = read_nonempty(boot_file)
            assert len(rows) == 80, f"{boot_file} should have exactly 80 rows, got {len(rows)}"
            assert all(row in probe_set for row in rows), f"{boot_file} contains a row not read from train_scaled.csv"

            distinct = len(set(rows))
            assert distinct >= 20, f"{boot_file} is not a genuine bootstrap sample: only {distinct} distinct source rows"
            assert distinct < 80, f"{boot_file} contains every row exactly once, indicating sampling without replacement"
            samples.append(tuple(rows))

        assert len(set(samples)) > 1, "All five bootstrap datasets are identical; independent RANDOM sampling was not performed"
    finally:
        with open(train_path, "wb") as f:
            f.write(original)
        # Restore bootstrap outputs so the final files correspond to the real training data.
        subprocess.run(["bash", script_path], capture_output=True, text=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
