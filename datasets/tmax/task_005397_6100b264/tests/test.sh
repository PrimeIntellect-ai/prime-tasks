#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import gzip
import io
import json
import os
import subprocess

import pytest

PARSER_GO = "/app/vendor/github.com/buger/jsonparser/parser.go"
BYTESAFE = "/app/vendor/github.com/buger/jsonparser/bytesafe"
WORKSPACE = "/home/user/workspace/dataparser"
BINARY = "/home/user/workspace/dataparser/dataparser"
DATASET = "/home/user/raw_data/sensors.jsonl"
TARGET = "/home/user/organized_datasets/latest_readings.csv.gz"
SYMLINK = "/home/user/latest.csv.gz"
REBUILT = "/tmp/verifier_dataparser_rebuilt"


@pytest.fixture(scope="session")
def rebuilt_binary():
    try:
        result = subprocess.run(
            ["go", "build", "-mod=vendor", "-o", REBUILT, "."],
            cwd=WORKSPACE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
            check=False,
        )
    except Exception as exc:
        pytest.fail(f"Failed to rebuild dataparser from the repaired source: {exc}")
    assert result.returncode == 0, (
        "Rebuilding dataparser from the repaired source failed:\n"
        + result.stderr.decode("utf-8", errors="replace")
    )
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)
    return REBUILT


def run_parser(path, input_bytes):
    try:
        result = subprocess.run(
            [path],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
    except Exception as exc:
        pytest.fail(f"Could not execute {path}: {exc}")
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}: "
        + result.stderr.decode("utf-8", errors="replace")
    )
    return result.stdout


def expected_from_clean_dataset():
    with open(DATASET, "rb") as handle:
        raw_lines = handle.read().splitlines()

    assert all(not line.startswith(b"DEBUG_MACRO::") for line in raw_lines), (
        "DEBUG_MACRO boilerplate lines were not stripped from sensors.jsonl"
    )
    assert len(raw_lines) == 5000, (
        f"Expected all 5000 sensor records to remain after cleaning, found {len(raw_lines)}"
    )

    expected_rows = []
    for line_number, raw_line in enumerate(raw_lines, 1):
        assert raw_line.strip(), f"Unexpected blank line at sensors.jsonl:{line_number}"
        try:
            record = json.loads(raw_line, parse_int=str, parse_float=str)
        except Exception as exc:
            pytest.fail(f"Invalid JSON at sensors.jsonl:{line_number}: {exc}")
        assert isinstance(record, dict), f"Record {line_number} is not a JSON object"
        for field in ("timestamp", "sensor_id", "reading_value"):
            assert field in record, f"Record {line_number} is missing {field}"
        values = [record["timestamp"], record["sensor_id"], record["reading_value"]]
        assert all(isinstance(value, str) for value in values), (
            f"Record {line_number} has an unsupported field type"
        )
        assert all("," not in value and "\n" not in value and "\r" not in value for value in values)
        expected_rows.append(tuple(values))

    expected_text = "timestamp,sensor_id,reading_value\n" + "".join(
        f"{timestamp},{sensor_id},{reading_value}\n"
        for timestamp, sensor_id, reading_value in expected_rows
    )
    return expected_rows, expected_text.encode("utf-8")


def test_vendored_package_parser_go_fixed():
    assert os.path.isfile(PARSER_GO), f"File not found: {PARSER_GO}"
    with open(PARSER_GO, "r") as handle:
        content = handle.read()
    assert "math/rand/v2" not in content, (
        f"Expected corrupted import 'math/rand/v2' to be removed from {PARSER_GO}"
    )
    assert "math/rand" in content, f"Expected correct import 'math/rand' in {PARSER_GO}"


def test_bytesafe_module_fixed():
    assert os.path.exists(BYTESAFE), f"Expected bytesafe module to be accessible at {BYTESAFE}"
    assert os.path.isdir(BYTESAFE), f"Expected {BYTESAFE} to be a directory (or symlink to a directory)"


def test_dataparser_compiled(rebuilt_binary):
    assert os.path.isfile(BINARY), f"Expected compiled binary at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Expected {BINARY} to be executable"
    with open(BINARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"Expected {BINARY} to be a compiled ELF executable"

    synthetic = (
        b'{"timestamp":"alpha","sensor_id":"sensor_x","reading_value":12.34}\n'
        b'DEBUG_MACRO:: invalid input\n'
        b'{"timestamp":"beta","sensor_id":"sensor_y","reading_value":0}\n'
        b'{"timestamp":"missing","sensor_id":"sensor_z"}\n'
        b'not json\n'
    )
    expected = (
        b"timestamp,sensor_id,reading_value\n"
        b"alpha,sensor_x,12.34\n"
        b"beta,sensor_y,0\n"
    )
    assert run_parser(BINARY, synthetic) == expected
    assert run_parser(rebuilt_binary, synthetic) == expected


def test_output_file_and_metric(rebuilt_binary):
    assert os.path.islink(SYMLINK), f"Symlink not created at {SYMLINK}"
    assert os.path.isfile(TARGET), f"Target file not found at {TARGET}"
    real_path = os.path.realpath(SYMLINK)
    assert os.path.realpath(TARGET) == real_path, "Symlink does not point to the expected target"

    size = os.path.getsize(real_path)
    try:
        with gzip.open(real_path, "rb") as handle:
            output = handle.read()
    except Exception as exc:
        pytest.fail(f"Failed to read {real_path} as gzip: {exc}")

    expected_rows, expected_output = expected_from_clean_dataset()

    try:
        decoded = output.decode("utf-8")
        csv_rows = list(csv.reader(io.StringIO(decoded, newline="")))
    except Exception as exc:
        pytest.fail(f"Compressed output is not valid UTF-8 CSV: {exc}")

    assert len(csv_rows) > 4500, f"Not enough data parsed. Expected > 4500 rows, found {len(csv_rows)}"
    assert csv_rows and csv_rows[0] == ["timestamp", "sensor_id", "reading_value"], (
        "CSV header must be timestamp,sensor_id,reading_value"
    )
    assert all(len(row) == 3 for row in csv_rows), "Every CSV row must contain exactly three fields"
    assert [tuple(row) for row in csv_rows[1:]] == expected_rows, (
        "CSV fields or values do not match the cleaned sensors.jsonl records"
    )
    assert output == expected_output, "Compressed CSV content does not exactly match the required parser output"

    with open(DATASET, "rb") as handle:
        dataset_input = handle.read()
    assert run_parser(BINARY, dataset_input) == expected_output, (
        "The submitted dataparser executable does not produce the compressed artifact's content"
    )
    assert run_parser(rebuilt_binary, dataset_input) == expected_output, (
        "A fresh build from the repaired source does not produce the required content"
    )

    assert size <= 25000, (
        f"File size {size} exceeds threshold of 25000 bytes. Ensure debug lines were stripped and gzip compression was used."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
