#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
from decimal import Decimal
from pathlib import Path

import pytest

OUTPUT_FILE = "/home/user/sensor_risk_report.csv"
INPUT_FILE = "/home/user/sensor_data.csv"


def test_output_file_exists():
    """Test that the output report file was created."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not found."


def test_output_file_format_and_values():
    """Test the content, formatting, and calculations of the output report."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not found."

    with open(OUTPUT_FILE, mode='r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The output CSV file is empty."

    expected_header = ['sensor_id', 'mean_temp', 'max_humidity', 'risk_score']
    assert rows[0] == expected_header, f"Expected header {expected_header}, but got {rows[0]}."

    data_rows = rows[1:]
    assert len(data_rows) == 3, f"Expected 3 data rows, but found {len(data_rows)}."

    expected_data = [
        ['S1', '22.50', '47.50', '61.75'],
        ['S2', '18.25', '62.00', '66.98'],
        ['S3', '30.25', '35.00', '63.38']
    ]

    sensor_ids = [row[0] for row in data_rows]
    assert sensor_ids == ['S1', 'S2', 'S3'], f"Rows must be sorted by sensor_id. Got {sensor_ids}."

    for i, (actual_row, expected_row) in enumerate(zip(data_rows, expected_data)):
        assert len(actual_row) == 4, f"Row {i+1} does not have exactly 4 columns: {actual_row}"

        sensor_id, mean_temp, max_humidity, risk_score = actual_row
        exp_id, exp_temp, exp_hum, exp_score = expected_row

        assert sensor_id == exp_id, f"Row {i+1}: Expected sensor_id '{exp_id}', got '{sensor_id}'."

        for val_name, actual_val, exp_val in [
            ('mean_temp', mean_temp, exp_temp),
            ('max_humidity', max_humidity, exp_hum),
            ('risk_score', risk_score, exp_score)
        ]:
            try:
                float_val = float(actual_val)
            except ValueError:
                pytest.fail(f"Row {i+1}: {val_name} '{actual_val}' is not a valid number.")

            assert abs(float_val - float(exp_val)) < 0.015, \
                f"Row {i+1}: Expected {val_name} ~{exp_val}, got {actual_val}."

            parts = actual_val.split('.')
            assert len(parts) == 2 and len(parts[1]) == 2, \
                f"Row {i+1}: {val_name} '{actual_val}' is not rounded to exactly 2 decimal places."


def _two_decimal(value):
    return f"{value:.2f}"


def test_python_script_executes_etl_on_unseen_input():
    scripts = sorted(
        path for path in Path('/home/user').rglob('*.py')
        if path.is_file()
    )
    assert scripts, "No Python script was found under /home/user."

    input_path = Path(INPUT_FILE)
    output_path = Path(OUTPUT_FILE)
    original_input = input_path.read_bytes()
    original_output = output_path.read_bytes() if output_path.is_file() else None

    token = secrets.token_hex(4)
    sensor_ids = [f"X{token}_z", f"X{token}_a", f"X{token}_m", f"X{token}_b"]
    specs = {}
    for sensor_id in sensor_ids:
        temp_tenths = secrets.randbelow(501) - 100
        humidity_tenths = 300 + secrets.randbelow(651)
        specs[sensor_id] = (temp_tenths, humidity_tenths)

    fixture_rows = []
    for index, sensor_id in enumerate(reversed(sensor_ids)):
        temp_tenths, humidity_tenths = specs[sensor_id]
        temperatures = [temp_tenths - 7, temp_tenths + 2, temp_tenths + 5]
        humidities = [humidity_tenths - 17, humidity_tenths, humidity_tenths - 8]
        for sample, (temperature, humidity) in enumerate(zip(temperatures, humidities)):
            fixture_rows.append([
                f"2026-01-{index + 1:02d}T00:0{sample}:00Z",
                sensor_id,
                str(Decimal(temperature) / Decimal(10)),
                str(Decimal(humidity) / Decimal(10)),
            ])

    expected_rows = []
    for sensor_id in sorted(sensor_ids):
        temp_tenths, humidity_tenths = specs[sensor_id]
        risk_cents = (15 * temp_tenths) + (8 * humidity_tenths) - 1000
        expected_rows.append([
            sensor_id,
            _two_decimal(Decimal(temp_tenths) / Decimal(10)),
            _two_decimal(Decimal(humidity_tenths) / Decimal(10)),
            _two_decimal(Decimal(risk_cents) / Decimal(100)),
        ])

    expected = [['sensor_id', 'mean_temp', 'max_humidity', 'risk_score']] + expected_rows
    failures = []

    try:
        for script in scripts:
            with input_path.open('w', newline='') as f:
                writer = csv.writer(f, lineterminator='\n')
                writer.writerow(['timestamp', 'sensor_id', 'temperature', 'humidity'])
                writer.writerows(fixture_rows)
            if output_path.exists():
                output_path.unlink()

            try:
                result = subprocess.run(
                    ['python3', str(script)],
                    cwd='/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=20,
                )
            except Exception as exc:
                failures.append(f"{script}: execution failed: {exc}")
                continue

            if result.returncode != 0:
                failures.append(f"{script}: exited with status {result.returncode}")
                continue
            if not output_path.is_file():
                failures.append(f"{script}: did not create {OUTPUT_FILE}")
                continue

            try:
                with output_path.open(newline='') as f:
                    actual = list(csv.reader(f))
            except Exception as exc:
                failures.append(f"{script}: output could not be read: {exc}")
                continue

            if actual == expected:
                return
            failures.append(f"{script}: output did not match the derived unseen-input result")

        pytest.fail("No discovered Python script correctly performed the ETL when executed. " + "; ".join(failures))
    finally:
        input_path.write_bytes(original_input)
        if original_output is None:
            if output_path.exists():
                output_path.unlink()
        else:
            output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
