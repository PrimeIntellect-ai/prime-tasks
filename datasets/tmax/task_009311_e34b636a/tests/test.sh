#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import stat
import subprocess
import pytest

RAW_PATH = "/home/user/raw_data.csv"
SOURCE_PATH = "/home/user/filter_data.c"
BINARY_PATH = "/home/user/filter_data"
FILTERED_PATH = "/home/user/filtered_data.csv"
STATS_PATH = "/home/user/stats.txt"
REBUILT_PATH = "/tmp/filter_data_from_source"


def expected_for_raw(raw_path):
    filtered_rows = []
    y_values = []

    with open(raw_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["id", "f1", "f2", "f3"]
        for row in reader:
            if not row:
                continue
            id_val = int(row[0])
            f1 = float(row[1])
            f2 = float(row[2])
            f3 = float(row[3])
            y = 2.0 + 0.5 * f1 - 1.2 * f2 + 0.8 * f3
            if y > 0.0:
                filtered_rows.append([
                    str(id_val), f"{f1:.4f}", f"{f2:.4f}",
                    f"{f3:.4f}", f"{y:.4f}"
                ])
                y_values.append(y)

    n = len(y_values)
    assert n > 1
    mean_y = sum(y_values) / n
    var_y = sum((y - mean_y) ** 2 for y in y_values) / (n - 1)
    se_y = math.sqrt(var_y) / math.sqrt(n)
    stats = {
        "Mean": f"{mean_y:.4f}",
        "CI_Lower": f"{mean_y - 1.96 * se_y:.4f}",
        "CI_Upper": f"{mean_y + 1.96 * se_y:.4f}",
    }
    return filtered_rows, stats


def validate_current_outputs():
    expected_rows, expected_stats = expected_for_raw(RAW_PATH)
    assert os.path.exists(FILTERED_PATH), f"Missing {FILTERED_PATH}"
    with open(FILTERED_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        assert next(reader, None) == ["id", "f1", "f2", "f3", "y"]
        actual_rows = list(reader)
    assert actual_rows == expected_rows

    assert os.path.exists(STATS_PATH), f"Missing {STATS_PATH}"
    actual_stats = {}
    with open(STATS_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if line and ":" in line:
                key, value = line.split(":", 1)
                actual_stats[key.strip()] = value.strip()
    for key in ["Mean", "CI_Lower", "CI_Upper"]:
        assert key in actual_stats, f"Missing {key} in stats.txt"
        assert actual_stats[key] == expected_stats[key]


def run_on_data(program, raw_text):
    with open(RAW_PATH, "w") as f:
        f.write(raw_text)
    for path in [FILTERED_PATH, STATS_PATH]:
        if os.path.lexists(path):
            os.unlink(path)
    result = subprocess.run(
        [program], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    validate_current_outputs()


def test_required_c_source_and_executable_work():
    assert os.path.isfile(SOURCE_PATH), f"Missing {SOURCE_PATH}"
    assert os.path.isfile(BINARY_PATH), f"Missing {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled executable"

    build = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", REBUILT_PATH, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert build.returncode == 0, f"C source did not compile:\n{build.stderr}"

    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()
    try:
        run_on_data(BINARY_PATH, """id,f1,f2,f3
101,1.0000,1.0000,1.0000
102,0.0000,10.0000,0.0000
103,-2.0000,0.0000,0.0000
104,3.3333,2.2222,-1.1111
105,8.2500,1.1250,4.5000
""")
        run_on_data(REBUILT_PATH, """id,f1,f2,f3
201,0.1250,0.2500,0.3750
202,9.7500,9.5000,0.1250
203,-1.5000,-2.2500,3.7500
204,4.4444,3.3333,2.2222
205,0.0000,0.0000,0.0000
206,-10.0000,0.0000,0.0000
""")
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        for path in [FILTERED_PATH, STATS_PATH]:
            if os.path.lexists(path):
                os.unlink(path)
        restored = subprocess.run(
            [BINARY_PATH], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10
        )
        assert restored.returncode == 0, restored.stderr


def compute_expected_data():
    raw_path = "/home/user/raw_data.csv"
    assert os.path.exists(raw_path), f"Missing {raw_path}"

    filtered_rows = []
    y_values = []

    with open(raw_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            if not row:
                continue
            id_val = int(row[0])
            f1 = float(row[1])
            f2 = float(row[2])
            f3 = float(row[3])

            y = 2.0 + 0.5 * f1 - 1.2 * f2 + 0.8 * f3

            if y > 0.0:
                filtered_rows.append([str(id_val), f"{f1:.4f}", f"{f2:.4f}", f"{f3:.4f}", f"{y:.4f}"])
                y_values.append(y)

    n = len(y_values)
    mean_y = sum(y_values) / n
    var_y = sum((y - mean_y) ** 2 for y in y_values) / (n - 1)
    se_y = math.sqrt(var_y) / math.sqrt(n)

    lower = mean_y - 1.96 * se_y
    upper = mean_y + 1.96 * se_y

    stats = {
        "Mean": f"{mean_y:.4f}",
        "CI_Lower": f"{lower:.4f}",
        "CI_Upper": f"{upper:.4f}"
    }

    return filtered_rows, stats


def test_filtered_data_csv():
    expected_rows, _ = compute_expected_data()
    out_path = "/home/user/filtered_data.csv"

    assert os.path.exists(out_path), f"Missing {out_path}"

    with open(out_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["id", "f1", "f2", "f3", "y"], "Incorrect header in filtered_data.csv"
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, found {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}"


def test_stats_txt():
    _, expected_stats = compute_expected_data()
    out_path = "/home/user/stats.txt"

    assert os.path.exists(out_path), f"Missing {out_path}"

    actual_stats = {}
    with open(out_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if ":" in line:
                k, v = line.split(":", 1)
                actual_stats[k.strip()] = v.strip()

    for key in ["Mean", "CI_Lower", "CI_Upper"]:
        assert key in actual_stats, f"Missing {key} in stats.txt"
        assert actual_stats[key] == expected_stats[key], f"Expected {key} to be {expected_stats[key]}, got {actual_stats[key]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
