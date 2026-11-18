#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import re
import subprocess
import unicodedata
from collections import Counter

import pytest

PROCESSED_LOGS_PATH = "/home/user/processed_logs.csv"
RAW_LOGS_PATH = "/home/user/raw_logs.txt"
PROJECT_PATH = "/home/user/log_processor"
CARGO_TOML_PATH = os.path.join(PROJECT_PATH, "Cargo.toml")
MAIN_RS_PATH = os.path.join(PROJECT_PATH, "src", "main.rs")


@pytest.fixture(scope="session", autouse=True)
def run_rust_program():
    assert os.path.isdir(PROJECT_PATH), f"Rust project directory {PROJECT_PATH} is missing."
    assert os.path.isfile(CARGO_TOML_PATH), f"Rust manifest {CARGO_TOML_PATH} is missing."
    assert os.path.isfile(MAIN_RS_PATH), f"Rust source file {MAIN_RS_PATH} is missing."

    if os.path.exists(PROCESSED_LOGS_PATH):
        os.remove(PROCESSED_LOGS_PATH)

    try:
        result = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", CARGO_TOML_PATH],
            cwd=PROJECT_PATH,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The Rust program did not finish within 180 seconds.")

    assert result.returncode == 0, (
        "The Rust project failed to compile or run.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def expected_rows_from_raw():
    pattern = re.compile(
        r"^\[(?P<timestamp>[^\]]+)\]\s+[^:]+:\s*(?P<message>.*?)\s+metrics:\{(?P<metrics>[^}]*)\}\s*$"
    )
    expected = []

    with open(RAW_LOGS_PATH, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            line = line.rstrip("\r\n")
            match = pattern.fullmatch(line)
            assert match is not None, f"Verifier could not parse raw log line {line_number}: {line!r}"

            metrics = []
            for item in match.group("metrics").split(";"):
                name, separator, value_text = item.partition("=")
                assert separator and name, f"Invalid metric on raw log line {line_number}: {item!r}"
                value = float(value_text)
                metrics.append((name, value))

            norm = math.sqrt(sum(value * value for _, value in metrics))
            if norm > 5.0:
                message = unicodedata.normalize("NFKC", match.group("message")).strip()
                for metric_name, metric_value in metrics:
                    expected.append(
                        (match.group("timestamp"), metric_name, metric_value, message)
                    )

    return expected


def test_processed_logs_exists():
    assert os.path.exists(PROCESSED_LOGS_PATH), f"Output file {PROCESSED_LOGS_PATH} was not created."
    assert os.path.isfile(PROCESSED_LOGS_PATH), f"{PROCESSED_LOGS_PATH} is not a file."


def test_processed_logs_format_and_content():
    assert os.path.exists(PROCESSED_LOGS_PATH), "Processed logs file is missing."

    with open(PROCESSED_LOGS_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty.")

        expected_header = ["timestamp", "metric_name", "metric_value", "message"]
        assert header == expected_header, f"Expected header {expected_header}, got {header}"

        rows = list(reader)

    assert len(rows) == 8, f"Expected exactly 8 rows in the output CSV, but found {len(rows)}."
    assert all(len(row) == 4 for row in rows), "Every output row must contain exactly four CSV fields."

    timestamps = [row[0] for row in rows]
    messages = [row[3] for row in rows]

    # Check Math Constraint (L2 > 5.0)
    assert '2023-10-01 10:00:00' not in timestamps, "Log entry with L2 norm == 5.0 was not filtered out."
    assert '2023-10-01 10:05:00' not in timestamps, "Log entry with L2 norm == 3.0 was not filtered out."
    assert '2023-10-01 10:20:00' not in timestamps, "Log entry with L2 norm == 3.0 was not filtered out."

    # Check Unicode Normalization and whitespace stripping
    assert "ff ligature test" in messages, "Ligature 'ﬀ' was not normalized to 'ff' using NFKC."
    assert "A bad string" in messages, "Fraktur '𝔄' was not normalized to 'A' or whitespace was not stripped."

    # Check Wide-Long Format Reshaping
    ts_101000_rows = [r for r in rows if r[0] == '2023-10-01 10:10:00']
    assert len(ts_101000_rows) == 3, f"Expected 3 rows for timestamp 10:10:00, got {len(ts_101000_rows)}"

    ts_102500_rows = [r for r in rows if r[0] == '2023-10-01 10:25:00']
    assert len(ts_102500_rows) == 2, f"Expected 2 rows for timestamp 10:25:00, got {len(ts_102500_rows)}"

    # Check specific row data for correctness
    # For 10:25:00, metrics a=5.0, b=5.0
    metrics_102500 = {(r[1], float(r[2])) for r in ts_102500_rows}
    assert metrics_102500 == {('a', 5.0), ('b', 5.0)}, f"Metrics for 10:25:00 are incorrect: {metrics_102500}"

    # Validate every output row against values independently recomputed from the raw log.
    actual = []
    for row_number, row in enumerate(rows, 2):
        try:
            metric_value = float(row[2])
        except ValueError:
            pytest.fail(f"Row {row_number} has a non-numeric metric value: {row[2]!r}")
        assert math.isfinite(metric_value), f"Row {row_number} has a non-finite metric value."
        actual.append((row[0], row[1], metric_value, row[3]))

    expected = expected_rows_from_raw()
    assert Counter(actual) == Counter(expected), (
        "The output rows do not exactly match the filtered, normalized, long-format "
        "rows recomputed from raw_logs.txt."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
