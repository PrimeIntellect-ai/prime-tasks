#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import subprocess

SCRIPT_PATH = '/home/user/run_pipeline.sh'
CPP_PATH = '/home/user/process_data.cpp'
CSV_PATH = '/home/user/data/sensors.csv'
OUTPUT_PATH = '/home/user/output/model_metrics.txt'
WORKDIR = '/home/user'


def test_run_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_cpp_file_exists():
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."


def expected_metrics(csv_path):
    x = []
    y = []
    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            x.append(float(row['temperature']))
            y.append(float(row['pressure']))

    n = len(x)
    assert n > 0, "CSV file has no data rows."

    mean_x = sum(x) / n
    mean_y = sum(y) / n
    numerator = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    denominator = sum((xi - mean_x) ** 2 for xi in x)
    assert denominator != 0, "Temperature values have zero variance."

    expected_m = numerator / denominator
    expected_c = mean_y - expected_m * mean_x
    expected_mse = sum(
        (yi - (expected_m * xi + expected_c)) ** 2
        for xi, yi in zip(x, y)
    ) / n
    return expected_m, expected_c, expected_mse


def check_model_metrics(csv_path, output_path):
    assert os.path.isfile(csv_path), f"Data file {csv_path} does not exist."
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    expected_m, expected_c, expected_mse = expected_metrics(csv_path)

    with open(output_path, 'r') as f:
        raw_lines = f.read().splitlines()

    assert len(raw_lines) == 3, \
        f"Expected exactly 3 lines in {output_path}, found {len(raw_lines)}."

    patterns = [
        r'^Slope: [-+]?(?:\d+\.\d{4})$',
        r'^Intercept: [-+]?(?:\d+\.\d{4})$',
        r'^MSE: [-+]?(?:\d+\.\d{4})$',
    ]
    for line, pattern in zip(raw_lines, patterns):
        assert re.fullmatch(pattern, line), \
            f"Invalid output line or precision: '{line}'"

    lines = [line.strip() for line in raw_lines if line.strip()]
    parsed_metrics = {}
    for line in lines:
        parts = line.split(':')
        assert len(parts) == 2, \
            f"Invalid line format in output: '{line}'. Expected 'Key: Value'."
        key = parts[0].strip()
        try:
            parsed_metrics[key] = float(parts[1].strip())
        except ValueError:
            assert False, f"Could not parse float value from line: '{line}'"

    assert 'Slope' in parsed_metrics, "Missing 'Slope' in output."
    assert 'Intercept' in parsed_metrics, "Missing 'Intercept' in output."
    assert 'MSE' in parsed_metrics, "Missing 'MSE' in output."

    tolerance = 0.0002
    assert abs(parsed_metrics['Slope'] - expected_m) <= tolerance, \
        f"Slope is incorrect. Expected ~{expected_m:.4f}, got {parsed_metrics['Slope']}"
    assert abs(parsed_metrics['Intercept'] - expected_c) <= tolerance, \
        f"Intercept is incorrect. Expected ~{expected_c:.4f}, got {parsed_metrics['Intercept']}"
    assert abs(parsed_metrics['MSE'] - expected_mse) <= tolerance, \
        f"MSE is incorrect. Expected ~{expected_mse:.4f}, got {parsed_metrics['MSE']}"


def test_model_metrics_output():
    # Require the submitted pipeline script to create both the executable and
    # metrics from scratch rather than accepting pre-created output.
    binary_path = os.path.join(WORKDIR, 'process_data')
    for path in (binary_path, OUTPUT_PATH):
        if os.path.lexists(path):
            os.remove(path)

    subprocess.run(
        [SCRIPT_PATH], cwd=WORKDIR, check=True, timeout=30,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    assert os.path.isfile(binary_path), \
        "Pipeline script did not create the process_data executable."
    assert os.access(binary_path, os.X_OK), \
        "The generated process_data file is not executable."
    check_model_metrics(CSV_PATH, OUTPUT_PATH)

    # Independently compile and execute the submitted C++ source against a
    # different dataset, preventing a script or output file with fixed answers
    # from passing in place of the requested C++ ETL implementation.
    with open(CSV_PATH, 'rb') as f:
        original_csv = f.read()
    with open(OUTPUT_PATH, 'rb') as f:
        original_output = f.read()

    verified_binary = '/tmp/process_data_verified'
    try:
        with open(CSV_PATH, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['id', 'temperature', 'pressure'])
            writer.writerows([
                [1, -7.25, 18.4],
                [2, -1.50, 4.2],
                [3, 2.75, -3.1],
                [4, 9.125, -17.8],
                [5, 15.50, -29.0],
                [6, 23.875, -48.6],
            ])

        subprocess.run(
            ['g++', '-O3', '-std=c++17', '-o', verified_binary, CPP_PATH],
            cwd=WORKDIR, check=True, timeout=30,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        if os.path.lexists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        subprocess.run(
            [verified_binary], cwd=WORKDIR, check=True, timeout=30,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        check_model_metrics(CSV_PATH, OUTPUT_PATH)
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        with open(OUTPUT_PATH, 'wb') as f:
            f.write(original_output)
        if os.path.exists(verified_binary):
            os.remove(verified_binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
