#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import csv
import re
import subprocess
from datetime import datetime, timedelta
import pytest

RAW_DATA_PATH = "/home/user/raw_sensor_logs.csv"
SCRIPT_PATH = "/home/user/process_data.py"
PROCESSED_DATA_PATH = "/home/user/processed_data.csv"


def get_expected_data():
    valid_sensors = {"TempSensor", "Temperatursensor", "温度計"}
    data_by_minute = {}
    min_time = None
    max_time = None

    with open(RAW_DATA_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            dt = datetime.strptime(row["timestamp"], "%Y-%m-%dT%H:%M:%SZ")
            minute_dt = dt.replace(second=0, microsecond=0)

            # The requested range is determined by every row in the raw dataset,
            # including rows belonging to non-temperature sensors.
            if min_time is None or minute_dt < min_time:
                min_time = minute_dt
            if max_time is None or minute_dt > max_time:
                max_time = minute_dt

            if row["sensor_name"] not in valid_sensors:
                continue

            reading = float(row["reading"])

            match = re.search(r"\{([^}]+)\}", row["notes"])
            op_code = match.group(1) if match else ""

            if minute_dt not in data_by_minute:
                data_by_minute[minute_dt] = {"readings": [], "op_codes": []}

            data_by_minute[minute_dt]["readings"].append(reading)
            if op_code:
                data_by_minute[minute_dt]["op_codes"].append(op_code)

    expected_rows = []
    if min_time is None:
        return expected_rows

    curr_time = min_time
    last_reading = None

    while curr_time <= max_time:
        ts_str = curr_time.strftime("%Y-%m-%dT%H:%M:%SZ")
        if curr_time in data_by_minute:
            readings = data_by_minute[curr_time]["readings"]
            op_codes = data_by_minute[curr_time]["op_codes"]

            avg_reading = sum(readings) / len(readings)
            avg_reading_rounded = f"{round(avg_reading, 2):.2f}"
            last_reading = avg_reading_rounded

            op_code = op_codes[-1] if op_codes else ""
            expected_rows.append([ts_str, "temperature", avg_reading_rounded, op_code])
        else:
            expected_rows.append([ts_str, "temperature", last_reading, "GAP"])

        curr_time += timedelta(minutes=1)

    return expected_rows


def uses_streaming_csv_or_chunked_pandas(source):
    tree = ast.parse(source, filename=SCRIPT_PATH)
    csv_modules = set()
    csv_readers = set()
    pandas_modules = set()
    pandas_read_csv = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "csv":
                    csv_modules.add(alias.asname or "csv")
                if alias.name == "pandas":
                    pandas_modules.add(alias.asname or "pandas")
        elif isinstance(node, ast.ImportFrom):
            if node.module == "csv":
                for alias in node.names:
                    if alias.name in {"reader", "DictReader"}:
                        csv_readers.add(alias.asname or alias.name)
            elif node.module == "pandas":
                for alias in node.names:
                    if alias.name == "read_csv":
                        pandas_read_csv.add(alias.asname or alias.name)

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue

        func = node.func
        if isinstance(func, ast.Attribute):
            if (
                func.attr in {"reader", "DictReader"}
                and isinstance(func.value, ast.Name)
                and func.value.id in csv_modules
            ):
                return True
            is_pandas_read_csv = (
                func.attr == "read_csv"
                and isinstance(func.value, ast.Name)
                and func.value.id in pandas_modules
            )
        else:
            is_pandas_read_csv = (
                isinstance(func, ast.Name) and func.id in pandas_read_csv
            )
            if isinstance(func, ast.Name) and func.id in csv_readers:
                return True

        if is_pandas_read_csv:
            for keyword in node.keywords:
                if keyword.arg == "chunksize" and not (
                    isinstance(keyword.value, ast.Constant)
                    and keyword.value.value is None
                ):
                    return True

    return False


def test_process_script_exists_streams_and_executes():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()

    try:
        streams = uses_streaming_csv_or_chunked_pandas(source)
    except SyntaxError as exc:
        pytest.fail(f"The processing script is not valid Python: {exc}")

    assert streams, (
        "The processing script must read with csv.reader/csv.DictReader or use "
        "pandas.read_csv with a chunksize argument."
    )

    if os.path.lexists(PROCESSED_DATA_PATH):
        os.remove(PROCESSED_DATA_PATH)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_processed_file_exists():
    """Test that the processed CSV file was created."""
    assert os.path.exists(PROCESSED_DATA_PATH), f"The file {PROCESSED_DATA_PATH} does not exist."
    assert os.path.isfile(PROCESSED_DATA_PATH), f"The path {PROCESSED_DATA_PATH} is not a file."


def test_processed_file_headers():
    """Test that the processed CSV has the correct headers."""
    with open(PROCESSED_DATA_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f"The file {PROCESSED_DATA_PATH} is empty.")

        expected_headers = ["timestamp", "sensor_name", "reading", "op_code"]
        assert headers == expected_headers, f"Expected headers {expected_headers}, got {headers}."


def test_processed_file_content():
    """Test that the processed CSV content exactly matches the expected resampled data."""
    expected_rows = get_expected_data()

    actual_rows = []
    with open(PROCESSED_DATA_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}. "
        "Check your start/end times and 1-minute interval logic."
    )

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, (
            f"Row {i+1} mismatch.\nExpected: {expected}\nActual: {actual}\n"
            "Check filtering, mean calculation, gap filling, and op_code extraction."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
