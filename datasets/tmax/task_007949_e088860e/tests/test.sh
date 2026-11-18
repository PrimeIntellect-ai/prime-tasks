#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import shutil
import subprocess
import tempfile

RAW = "/home/user/raw_sensor_data.csv"
SOURCE = "/home/user/process_data.cpp"
EXECUTABLE = "/home/user/process_data"
CLEANED = "/home/user/cleaned_data.csv"
REJECTED = "/home/user/rejected_data.csv"

CLEAN_HEADER = [
    "timestamp", "sensor_id", "temperature", "humidity",
    "rolling_mean", "rolling_stddev", "normalized_temp"
]
REJECT_HEADER = [
    "timestamp", "sensor_id", "temperature", "humidity", "error_reason"
]
FOUR_DECIMALS = re.compile(r"^-?\d+\.\d{4}$")


def compute_expected_data(rows):
    expected_rejected = []
    expected_cleaned = []
    window = []

    for row in rows:
        temp = float(row["temperature"])
        hum = float(row["humidity"])
        temp_invalid = not (-50.0 <= temp <= 50.0)
        hum_invalid = not (0.0 <= hum <= 100.0)

        if temp_invalid or hum_invalid:
            if temp_invalid and hum_invalid:
                reason = "invalid_temp_and_humidity"
            elif temp_invalid:
                reason = "invalid_temp"
            else:
                reason = "invalid_humidity"
            expected_rejected.append({**row, "error_reason": reason})
            continue

        window.append(temp)
        if len(window) > 5:
            window.pop(0)

        n = len(window)
        mean = sum(window) / n
        if n < 2:
            stddev = 0.0
            z = 0.0
        else:
            variance = sum((x - mean) ** 2 for x in window) / (n - 1)
            stddev = math.sqrt(variance)
            z = 0.0 if stddev == 0.0 else (temp - mean) / stddev

        expected_cleaned.append({
            **row,
            "rolling_mean": mean,
            "rolling_stddev": stddev,
            "normalized_temp": z,
        })

    return expected_rejected, expected_cleaned


def write_raw(rows):
    with open(RAW, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["timestamp", "sensor_id", "temperature", "humidity"])
        writer.writeheader()
        writer.writerows(rows)


def read_raw():
    with open(RAW, newline="") as f:
        return list(csv.DictReader(f))


def assert_original_number(actual, expected, label):
    try:
        value = float(actual)
    except ValueError as exc:
        raise AssertionError(f"{label} is not numeric: {actual!r}") from exc
    assert math.isfinite(value), f"{label} is not finite: {actual!r}"
    assert abs(value - float(expected)) < 1e-9, \
        f"{label} mismatch. Expected {expected}, got {actual}."


def validate_outputs(rows, case_name):
    expected_rejected, expected_cleaned = compute_expected_data(rows)

    assert os.path.exists(REJECTED), f"{case_name}: rejected_data.csv is missing."
    with open(REJECTED, newline="") as f:
        reader = csv.DictReader(f)
        actual_rejected = list(reader)
        rejected_header = reader.fieldnames

    assert rejected_header == REJECT_HEADER, \
        f"{case_name}: rejected header is incorrect. Got: {rejected_header}"
    assert len(actual_rejected) == len(expected_rejected), \
        f"{case_name}: expected {len(expected_rejected)} rejected rows, got {len(actual_rejected)}."

    for i, (actual, expected) in enumerate(zip(actual_rejected, expected_rejected)):
        assert actual["timestamp"] == expected["timestamp"], \
            f"{case_name}: rejected row {i} timestamp mismatch."
        assert actual["sensor_id"] == expected["sensor_id"], \
            f"{case_name}: rejected row {i} sensor_id mismatch."
        assert_original_number(actual["temperature"], expected["temperature"],
                               f"{case_name}: rejected row {i} temperature")
        assert_original_number(actual["humidity"], expected["humidity"],
                               f"{case_name}: rejected row {i} humidity")
        assert actual["error_reason"] == expected["error_reason"], \
            f"{case_name}: rejected row {i} error_reason mismatch."

    assert os.path.exists(CLEANED), f"{case_name}: cleaned_data.csv is missing."
    with open(CLEANED, newline="") as f:
        reader = csv.DictReader(f)
        actual_cleaned = list(reader)
        cleaned_header = reader.fieldnames

    assert cleaned_header == CLEAN_HEADER, \
        f"{case_name}: cleaned header is incorrect. Got: {cleaned_header}"
    assert len(actual_cleaned) == len(expected_cleaned), \
        f"{case_name}: expected {len(expected_cleaned)} cleaned rows, got {len(actual_cleaned)}."

    for i, (actual, expected) in enumerate(zip(actual_cleaned, expected_cleaned)):
        assert actual["timestamp"] == expected["timestamp"], \
            f"{case_name}: cleaned row {i} timestamp mismatch."
        assert actual["sensor_id"] == expected["sensor_id"], \
            f"{case_name}: cleaned row {i} sensor_id mismatch."
        assert_original_number(actual["temperature"], expected["temperature"],
                               f"{case_name}: cleaned row {i} temperature")
        assert_original_number(actual["humidity"], expected["humidity"],
                               f"{case_name}: cleaned row {i} humidity")

        for column in ["rolling_mean", "rolling_stddev", "normalized_temp"]:
            text = actual[column].strip()
            assert FOUR_DECIMALS.fullmatch(text), \
                f"{case_name}: cleaned row {i} {column} does not have exactly 4 decimal places: {text!r}"
            value = float(text)
            assert math.isfinite(value), \
                f"{case_name}: cleaned row {i} {column} is not finite."
            assert abs(value - expected[column]) < 1e-3, \
                (f"{case_name}: cleaned row {i} {column} mismatch. "
                 f"Expected {expected[column]:.4f}, got {text}.")


def run_case(binary, rows, case_name):
    write_raw(rows)
    for path in (CLEANED, REJECTED):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        [binary], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, \
        f"{case_name}: program exited with {result.returncode}. stderr: {result.stderr}"
    validate_outputs(rows, case_name)


def test_complete_pipeline():
    # Preserve the original verifier's existence and executability assertions.
    assert os.path.exists(SOURCE), "C++ source file /home/user/process_data.cpp is missing."
    assert os.path.isfile(SOURCE), "/home/user/process_data.cpp is not a regular file."
    assert os.path.exists(EXECUTABLE), "Executable /home/user/process_data is missing. Did it compile successfully?"
    assert os.path.isfile(EXECUTABLE), "/home/user/process_data is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/process_data is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/process_data is not a compiled native executable."
    assert os.path.exists(RAW), f"Raw data file {RAW} is missing."

    saved = {}
    for path in (RAW, CLEANED, REJECTED):
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()

    compiled = os.path.join(tempfile.mkdtemp(prefix="pipeline_check_"), "process_data")
    try:
        compile_result = subprocess.run(
            ["g++", "-O2", "-std=c++17", SOURCE, "-o", compiled],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_result.returncode == 0, \
            f"process_data.cpp failed to compile: {compile_result.stderr}"

        # Execute the submitted executable on the original dataset, preserving all
        # checks made by the old verifier and adding comparisons of copied fields.
        original_rows = read_raw()
        run_case(EXECUTABLE, original_rows, "submitted executable/original input")

        dynamic_rows = [
            {"timestamp": "2100", "sensor_id": "edge-low", "temperature": "-50.0", "humidity": "0.0"},
            {"timestamp": "2101", "sensor_id": "edge-high", "temperature": "50.0", "humidity": "100.0"},
            {"timestamp": "2102", "sensor_id": "bad-temp", "temperature": "50.25", "humidity": "47.5"},
            {"timestamp": "2103", "sensor_id": "bad-hum", "temperature": "7.5", "humidity": "-0.25"},
            {"timestamp": "2104", "sensor_id": "bad-both", "temperature": "-50.25", "humidity": "100.25"},
            {"timestamp": "2105", "sensor_id": "A", "temperature": "10.0", "humidity": "10.0"},
            {"timestamp": "2106", "sensor_id": "B", "temperature": "10.0", "humidity": "20.0"},
            {"timestamp": "2107", "sensor_id": "C", "temperature": "10.0", "humidity": "30.0"},
            {"timestamp": "2108", "sensor_id": "A", "temperature": "30.0", "humidity": "40.0"},
            {"timestamp": "2109", "sensor_id": "B", "temperature": "-10.0", "humidity": "50.0"},
            {"timestamp": "2110", "sensor_id": "C", "temperature": "25.0", "humidity": "60.0"},
        ]
        run_case(EXECUTABLE, dynamic_rows, "submitted executable/dynamic input")

        source_rows = [
            {"timestamp": "3100", "sensor_id": "X", "temperature": "3.0", "humidity": "33.0"},
            {"timestamp": "3101", "sensor_id": "Y", "temperature": "3.0", "humidity": "44.0"},
            {"timestamp": "3102", "sensor_id": "Z", "temperature": "-75.0", "humidity": "150.0"},
            {"timestamp": "3103", "sensor_id": "X", "temperature": "9.0", "humidity": "55.0"},
            {"timestamp": "3104", "sensor_id": "Y", "temperature": "15.0", "humidity": "66.0"},
            {"timestamp": "3105", "sensor_id": "Z", "temperature": "21.0", "humidity": "77.0"},
            {"timestamp": "3106", "sensor_id": "X", "temperature": "27.0", "humidity": "88.0"},
            {"timestamp": "3107", "sensor_id": "Y", "temperature": "0.0", "humidity": "101.0"},
            {"timestamp": "3108", "sensor_id": "Z", "temperature": "-9.0", "humidity": "99.0"},
        ]
        run_case(compiled, source_rows, "freshly compiled source/dynamic input")
    finally:
        for path in (RAW, CLEANED, REJECTED):
            if path in saved:
                with open(path, "wb") as f:
                    f.write(saved[path])
            elif os.path.lexists(path):
                os.remove(path)
        shutil.rmtree(os.path.dirname(compiled), ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
