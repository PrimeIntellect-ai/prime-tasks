#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import struct
import subprocess
import pytest


def parse_raw_sensors(filepath):
    """Parses the raw sensors file and returns a list of lists of strings."""
    data = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = re.search(r'F1=([^\s|]+)\s*\|\s*F2=([^\s|]+)\s*\|\s*F3=([^\s|]+)\s*\|\s*F4=([^\s|]+)', line)
            if match:
                data.append([match.group(1), match.group(2), match.group(3), match.group(4)])
    return data


def f32(value):
    return struct.unpack('f', struct.pack('f', float(value)))[0]


def f32_add(a, b):
    return f32(f32(a) + f32(b))


def f32_sub(a, b):
    return f32(f32(a) - f32(b))


def f32_mul(a, b):
    return f32(f32(a) * f32(b))


def expected_float_lines(raw_path):
    lines = []
    half = f32(0.5)
    for row in parse_raw_sensors(raw_path):
        f1, f2, f3, f4 = [f32(x) for x in row]
        pc1 = f32_add(f32_add(f32_add(f32_mul(half, f1), f32_mul(half, f2)), f32_mul(half, f3)), f32_mul(half, f4))
        pc2 = f32_sub(f32_add(f32_sub(f32_mul(half, f1), f32_mul(half, f2)), f32_mul(half, f3)), f32_mul(half, f4))
        lines.append(f"{pc1:.6f},{pc2:.6f}")
    return lines


def expected_double_lines(raw_path):
    lines = []
    for row in parse_raw_sensors(raw_path):
        f1, f2, f3, f4 = map(float, row)
        pc1 = 0.5 * f1 + 0.5 * f2 + 0.5 * f3 + 0.5 * f4
        pc2 = 0.5 * f1 - 0.5 * f2 + 0.5 * f3 - 0.5 * f4
        lines.append(f"{pc1:.6f},{pc2:.6f}")
    return lines


def test_00_dim_reduce_exists_compiles_and_runs():
    source_path = "/home/user/dim_reduce.c"
    executable_path = "/home/user/dim_reduce"

    assert os.path.exists(source_path), f"{source_path} does not exist."
    assert not os.path.islink(source_path), f"{source_path} must be a regular C source file, not a symlink."
    assert stat.S_ISREG(os.stat(source_path).st_mode), f"{source_path} is not a regular file."

    if os.path.lexists(executable_path):
        os.remove(executable_path)
    subprocess.run(
        ["gcc", "-O3", "-o", executable_path, source_path],
        check=True,
        timeout=30,
    )
    assert os.path.isfile(executable_path), "Compilation did not create /home/user/dim_reduce."

    for path in ("/home/user/projected_float.csv", "/home/user/projected_double.csv"):
        if os.path.lexists(path):
            os.remove(path)

    subprocess.run([executable_path], check=True, timeout=30, cwd="/home/user")

    assert os.path.isfile("/home/user/projected_float.csv"), "The compiled program did not create projected_float.csv."
    assert os.path.isfile("/home/user/projected_double.csv"), "The compiled program did not create projected_double.csv."


def test_features_csv():
    features_path = "/home/user/features.csv"
    raw_path = "/home/user/raw_sensors.txt"

    assert os.path.exists(features_path), f"{features_path} does not exist."
    assert os.path.exists(raw_path), f"{raw_path} does not exist."

    expected_data = parse_raw_sensors(raw_path)

    with open(features_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_data), "Number of rows in features.csv does not match raw_sensors.txt."

    for i, (actual_line, expected_row) in enumerate(zip(actual_lines, expected_data)):
        expected_line = ",".join(expected_row)
        assert actual_line == expected_line, f"Row {i+1} in features.csv is incorrect. Expected {expected_line}, got {actual_line}"


def test_projected_double_csv():
    raw_path = "/home/user/raw_sensors.txt"
    double_path = "/home/user/projected_double.csv"

    assert os.path.exists(double_path), f"{double_path} does not exist."

    expected_data = parse_raw_sensors(raw_path)

    with open(double_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_data), "Number of rows in projected_double.csv is incorrect."

    for i, (actual_line, expected_row) in enumerate(zip(actual_lines, expected_data)):
        f1, f2, f3, f4 = map(float, expected_row)
        pc1 = 0.5 * f1 + 0.5 * f2 + 0.5 * f3 + 0.5 * f4
        pc2 = 0.5 * f1 - 0.5 * f2 + 0.5 * f3 - 0.5 * f4

        parts = actual_line.split(',')
        assert len(parts) == 2, f"Row {i+1} in projected_double.csv does not have 2 columns."

        actual_pc1, actual_pc2 = map(float, parts)

        assert abs(actual_pc1 - pc1) < 1e-5, f"Row {i+1} PC1 double mismatch. Expected ~{pc1}, got {actual_pc1}"
        assert abs(actual_pc2 - pc2) < 1e-5, f"Row {i+1} PC2 double mismatch. Expected ~{pc2}, got {actual_pc2}"


def test_projected_float_csv_uses_single_precision():
    raw_path = "/home/user/raw_sensors.txt"
    float_path = "/home/user/projected_float.csv"

    assert os.path.exists(float_path), f"{float_path} does not exist."

    with open(float_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    expected_lines = expected_float_lines(raw_path)
    assert len(actual_lines) == len(expected_lines), "Number of rows in projected_float.csv is incorrect."

    for i, (actual_line, expected_line) in enumerate(zip(actual_lines, expected_lines)):
        assert re.fullmatch(r'-?\d+\.\d{6},-?\d+\.\d{6}', actual_line), f"Row {i+1} in projected_float.csv is not formatted with exactly 6 decimal places."
        assert actual_line == expected_line, f"Row {i+1} single-precision projection mismatch. Expected {expected_line}, got {actual_line}"


def test_max_error_txt():
    float_path = "/home/user/projected_float.csv"
    double_path = "/home/user/projected_double.csv"
    error_path = "/home/user/max_error.txt"
    raw_path = "/home/user/raw_sensors.txt"

    assert os.path.exists(float_path), f"{float_path} does not exist."
    assert os.path.exists(double_path), f"{double_path} does not exist."
    assert os.path.exists(error_path), f"{error_path} does not exist."

    with open(float_path, 'r') as f:
        float_lines = [line.strip() for line in f if line.strip()]

    with open(double_path, 'r') as f:
        double_lines = [line.strip() for line in f if line.strip()]

    assert len(float_lines) == len(double_lines), "Mismatch in number of rows between float and double CSVs."

    max_diff = 0.0
    for fl_line, db_line in zip(float_lines, double_lines):
        fl_parts = list(map(float, fl_line.split(',')))
        db_parts = list(map(float, db_line.split(',')))

        for fl_val, db_val in zip(fl_parts, db_parts):
            diff = abs(fl_val - db_val)
            if diff > max_diff:
                max_diff = diff

    with open(error_path, 'r') as f:
        reported_error_str = f.read().strip()

    try:
        reported_error = float(reported_error_str)
    except ValueError:
        pytest.fail(f"Could not parse max_error.txt as a float: {reported_error_str}")

    assert abs(reported_error - max_diff) < 1e-5, f"max_error.txt mismatch. Expected ~{max_diff:.8f}, got {reported_error:.8f}"
    assert re.match(r'^\d+\.\d{8}$', reported_error_str), f"max_error.txt is not formatted to exactly 8 decimal places: {reported_error_str}"

    genuine_float = expected_float_lines(raw_path)
    genuine_double = expected_double_lines(raw_path)
    genuine_max = max(
        abs(fl_val - db_val)
        for fl_line, db_line in zip(genuine_float, genuine_double)
        for fl_val, db_val in zip(map(float, fl_line.split(',')), map(float, db_line.split(',')))
    )
    expected_error_str = f"{genuine_max:.8f}"
    assert reported_error_str == expected_error_str, f"max_error.txt must report the genuine float-vs-double difference. Expected {expected_error_str}, got {reported_error_str}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
