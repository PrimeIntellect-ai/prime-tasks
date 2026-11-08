#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import io
import math
import random
import subprocess
import pytest

SCRIPT_PATH = '/home/user/process_drift.py'
RAW_PATH = '/home/user/raw_configs.csv'
OUTPUT_PATH = '/home/user/validated_configs.csv'


def test_process_drift_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."


def test_validated_configs_exists_and_utf8():
    file_path = OUTPUT_PATH
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            f.read()
    except UnicodeDecodeError:
        pytest.fail(f"File {file_path} is not encoded in UTF-8.")


def test_validated_configs_content():
    file_path = OUTPUT_PATH
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    expected_data = [
        ('2023-10-03', 'AuthService', 'MemoryLimit', 2048, 1365.33),
        ('2023-10-04', 'AuthService', 'MemoryLimit', 4096, 2389.33),
        ('2023-10-05', 'AuthService', 'MemoryLimit', 8192, 4778.67),
        ('2023-10-03', 'AuthService', 'Timeout', 300, 200.0),
        ('2023-10-04', 'AuthService', 'Timeout', 1500, 666.67),
        ('2023-10-03', 'PaymentService', 'Timeout', 500, 500.0),
        ('2023-10-04', 'PaymentService', 'Timeout', 500, 500.0),
        ('2023-10-05', 'PaymentService', 'Timeout', 500, 500.0),
        ('2023-10-06', 'PaymentService', 'Timeout', 500, 500.0),
    ]

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("The CSV file is empty.")

        expected_header = ['Date', 'Service', 'Parameter', 'Value', 'RollingAvg']
        assert header == expected_header, f"Expected header {expected_header}, got {header}"

        actual_rows = list(reader)
        assert len(actual_rows) == len(expected_data), f"Expected {len(expected_data)} rows, got {len(actual_rows)} rows."

        for i, (actual, expected) in enumerate(zip(actual_rows, expected_data)):
            assert len(actual) == 5, f"Row {i+1} does not have exactly 5 columns."

            assert actual[0] == expected[0], f"Row {i+1} Date mismatch: expected {expected[0]}, got {actual[0]}"
            assert actual[1] == expected[1], f"Row {i+1} Service mismatch: expected {expected[1]}, got {actual[1]}"
            assert actual[2] == expected[2], f"Row {i+1} Parameter mismatch: expected {expected[2]}, got {actual[2]}"

            try:
                actual_value = int(actual[3])
            except ValueError:
                pytest.fail(f"Row {i+1} Value '{actual[3]}' is not a valid integer.")
            assert actual_value == expected[3], f"Row {i+1} Value mismatch: expected {expected[3]}, got {actual_value}"

            try:
                actual_rolling = float(actual[4])
            except ValueError:
                pytest.fail(f"Row {i+1} RollingAvg '{actual[4]}' is not a valid float.")

            assert math.isclose(actual_rolling, expected[4], rel_tol=1e-3), \
                f"Row {i+1} RollingAvg mismatch: expected {expected[4]}, got {actual_rolling}"


def test_script_executes_pipeline_on_unseen_utf16le_input():
    rng = random.SystemRandom()
    offset = rng.randint(1, 20)
    retry_values = [rng.randint(2, 80) for _ in range(6)]

    chronological_dates = [
        '2024-02-01', '2024-02-02', '2024-02-03',
        '2024-02-04', '2024-02-05', '2024-02-06'
    ]
    input_order = [3, 0, 5, 1, 4, 2]
    values_by_column = {
        'Gamma_Timeout': [100 + offset, 200 + offset, 300 + offset, 2800, 100, 100],
        'Alpha_MemoryLimit': [1000, 2000, 3000, 22000, 1000, 1000],
        'Beta_RetryCount': retry_values,
    }

    text = io.StringIO(newline='')
    writer = csv.writer(text, lineterminator='\n')
    columns = ['Date', 'Gamma_Timeout', 'Alpha_MemoryLimit', 'Beta_RetryCount']
    writer.writerow(columns)
    for index in input_order:
        writer.writerow([chronological_dates[index]] + [values_by_column[c][index] for c in columns[1:]])
    novel_raw = text.getvalue().encode('utf-16le')

    expected = []
    for source_column, values in values_by_column.items():
        service, parameter = source_column.split('_', 1)
        for index, date in enumerate(chronological_dates):
            if index < 2:
                continue
            rolling = sum(values[index - 2:index + 1]) / 3.0
            if parameter == 'Timeout' and rolling > 1000:
                continue
            if parameter == 'MemoryLimit' and rolling > 8192:
                continue
            expected.append((date, service, parameter, float(values[index]), round(rolling, 2)))
    expected.sort(key=lambda row: (row[1], row[2], row[0]))

    with open(RAW_PATH, 'rb') as f:
        original_raw = f.read()
    original_output = None
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, 'rb') as f:
            original_output = f.read()

    try:
        with open(RAW_PATH, 'wb') as f:
            f.write(novel_raw)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        result = subprocess.run(
            ['python3', SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(OUTPUT_PATH), "The script did not create validated_configs.csv."

        try:
            with open(OUTPUT_PATH, 'r', encoding='utf-8', newline='') as f:
                reader = csv.reader(f)
                header = next(reader, None)
                actual = list(reader)
        except UnicodeDecodeError:
            pytest.fail("The dynamically generated output is not UTF-8 encoded.")

        expected_header = ['Date', 'Service', 'Parameter', 'Value', 'RollingAvg']
        assert header == expected_header, f"Expected header {expected_header}, got {header}"
        assert len(actual) == len(expected), f"Expected {len(expected)} dynamic rows, got {len(actual)}."

        for index, (row, wanted) in enumerate(zip(actual, expected), start=1):
            assert len(row) == 5, f"Dynamic row {index} does not have exactly 5 columns."
            assert tuple(row[:3]) == wanted[:3], (
                f"Dynamic row {index} identity/order mismatch: expected {wanted[:3]}, got {tuple(row[:3])}"
            )
            try:
                value = float(row[3])
                rolling = float(row[4])
            except ValueError:
                pytest.fail(f"Dynamic row {index} has a non-numeric Value or RollingAvg: {row}")
            assert math.isfinite(value) and math.isfinite(rolling)
            assert value == wanted[3], f"Dynamic row {index} Value mismatch: expected {wanted[3]}, got {value}"
            assert math.isclose(rolling, wanted[4], rel_tol=0, abs_tol=0.005), (
                f"Dynamic row {index} RollingAvg mismatch: expected {wanted[4]}, got {rolling}"
            )
    finally:
        with open(RAW_PATH, 'wb') as f:
            f.write(original_raw)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
