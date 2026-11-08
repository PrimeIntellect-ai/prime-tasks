#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
from decimal import Decimal, InvalidOperation


def test_dataset_v1_content():
    file_path = "/home/user/dataset_v1.csv"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. Did you save the output dataset?"

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_rows = [
        ("1", "10.5", "2.0", "9.0", "1.5000", "0.7500", "1"),
        ("2", "11.0", "0.0", "11.0", "0.0000", "0.0000", "0"),
        ("3", "9.5", "1.5", "10.0", "-0.5000", "-0.3333", "1"),
        ("4", "12.1", "3.0", "10.0", "2.1000", "0.7000", "1"),
        ("5", "8.0", "2.0", "7.8", "0.2000", "0.1000", "0"),
    ]

    assert len(lines) == len(expected_rows) + 1, (
        f"Expected {len(expected_rows) + 1} lines in {file_path}, but found {len(lines)}."
    )
    assert lines[0] == "ts,f1,f2,f3,error,ratio,y", (
        f"Header in {file_path} is incorrect.\n"
        f"Expected: ts,f1,f2,f3,error,ratio,y\nActual:   {lines[0]}"
    )

    for line_number, (actual_line, expected) in enumerate(zip(lines[1:], expected_rows), start=2):
        actual = actual_line.split(",")
        assert len(actual) == 7, f"Line {line_number} in {file_path} must contain exactly 7 comma-separated fields."

        # The instruction constrains the numeric values, but not the textual
        # representation, of ts, f1, f2, and f3.
        for column_index, column_name in enumerate(("ts", "f1", "f2", "f3")):
            try:
                actual_value = Decimal(actual[column_index])
            except InvalidOperation:
                raise AssertionError(
                    f"Line {line_number} column {column_name} is not numeric: {actual[column_index]!r}"
                )
            expected_value = Decimal(expected[column_index])
            assert actual_value == expected_value, (
                f"Line {line_number} column {column_name} is incorrect. "
                f"Expected numeric value {expected_value}, got {actual[column_index]!r}."
            )

        # error and ratio are required to have exactly four decimal places.
        assert actual[4] == expected[4], (
            f"Line {line_number} error is incorrect or not formatted to exactly four decimal places.\n"
            f"Expected: {expected[4]}\nActual:   {actual[4]}"
        )
        assert actual[5] == expected[5], (
            f"Line {line_number} ratio is incorrect or not formatted to exactly four decimal places.\n"
            f"Expected: {expected[5]}\nActual:   {actual[5]}"
        )
        assert actual[6] == expected[6], (
            f"Line {line_number} label is incorrect. Expected {expected[6]}, got {actual[6]}."
        )


def test_metrics_content():
    file_path = "/home/user/metrics.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. Did you save the metrics file?"

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Total_Samples=5",
        "Positive_Class_Ratio=0.6000",
        "Mean_Error=0.6600",
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {file_path}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in {file_path} is incorrect.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
