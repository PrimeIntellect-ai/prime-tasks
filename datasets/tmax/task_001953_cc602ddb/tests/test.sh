#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from collections import defaultdict

LONG_FORMAT_PATH = "/home/user/output/long_format.csv"
SAMPLE_PATH = "/home/user/output/sample.csv"
PIPELINE_LOG_PATH = "/home/user/pipeline.log"
SOURCE_PATH = "/home/user/process.cpp"
BINARY_PATH = "/home/user/process"
INPUT_PATH = "/home/user/input/feedback.csv"
COMPILED_SOURCE_PATH = "/tmp/process_from_source"

EXPECTED_HEADER = ["UserID", "Region", "Day", "ProductID", "Sentiment", "ErrorCode"]

EXPECTED_LONG_ROWS = [
    ["U01", "NA", "Mon", "AppA", "positive", "none"],
    ["U01", "NA", "Tue", "AppB", "negative", "E100"],
    ["U01", "NA", "Wed", "AppA", "neutral", "none"],
    ["U02", "EU", "Mon", "AppC", "positive", "none"],
    ["U02", "EU", "Fri", "AppA", "negative", "E500"],
    ["U03", "NA", "Tue", "AppB", "negative", "E100"],
    ["U03", "NA", "Thu", "AppC", "positive", "none"],
    ["U04", "NA", "Wed", "AppA", "positive", "none"],
    ["U04", "NA", "Fri", "AppC", "positive", "none"],
    ["U05", "EU", "Mon", "AppA", "neutral", "none"],
    ["U05", "EU", "Tue", "AppB", "negative", "E200"],
    ["U05", "EU", "Wed", "AppB", "negative", "E201"],
    ["U06", "AS", "Thu", "AppA", "positive", "none"],
    ["U06", "AS", "Fri", "AppC", "neutral", "none"],
]

EXPECTED_SAMPLE_ROWS = [
    ["U01", "NA", "Mon", "AppA", "positive", "none"],
    ["U03", "NA", "Thu", "AppC", "positive", "none"],
    ["U01", "NA", "Tue", "AppB", "negative", "E100"],
    ["U03", "NA", "Tue", "AppB", "negative", "E100"],
    ["U01", "NA", "Wed", "AppA", "neutral", "none"],
    ["U02", "EU", "Mon", "AppC", "positive", "none"],
    ["U02", "EU", "Fri", "AppA", "negative", "E500"],
    ["U05", "EU", "Tue", "AppB", "negative", "E200"],
    ["U05", "EU", "Wed", "AppB", "negative", "E201"],
    ["U05", "EU", "Mon", "AppA", "neutral", "none"],
    ["U06", "AS", "Thu", "AppA", "positive", "none"],
    ["U06", "AS", "Fri", "AppC", "neutral", "none"],
]


def read_csv(path):
    with open(path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        rows = list(reader)
    return header, rows


def test_long_format_csv():
    assert os.path.isfile(LONG_FORMAT_PATH), f"File {LONG_FORMAT_PATH} does not exist."
    header, rows = read_csv(LONG_FORMAT_PATH)
    assert header == EXPECTED_HEADER, f"Header in {LONG_FORMAT_PATH} is incorrect. Expected {EXPECTED_HEADER}, got {header}."
    sorted_expected = sorted(EXPECTED_LONG_ROWS)
    sorted_actual = sorted(rows)
    assert len(sorted_actual) == len(sorted_expected), f"Expected {len(sorted_expected)} rows in {LONG_FORMAT_PATH}, but got {len(sorted_actual)}."
    assert sorted_actual == sorted_expected, f"Rows in {LONG_FORMAT_PATH} do not match expected data."


def test_sample_csv():
    assert os.path.isfile(SAMPLE_PATH), f"File {SAMPLE_PATH} does not exist."
    header, rows = read_csv(SAMPLE_PATH)
    assert header == EXPECTED_HEADER, f"Header in {SAMPLE_PATH} is incorrect. Expected {EXPECTED_HEADER}, got {header}."
    sorted_expected = sorted(EXPECTED_SAMPLE_ROWS)
    sorted_actual = sorted(rows)
    assert len(sorted_actual) == len(sorted_expected), f"Expected {len(sorted_expected)} rows in {SAMPLE_PATH}, but got {len(sorted_actual)}."
    assert sorted_actual == sorted_expected, f"Rows in {SAMPLE_PATH} do not match the expected stratified sample."


def test_pipeline_log():
    assert os.path.isfile(PIPELINE_LOG_PATH), f"File {PIPELINE_LOG_PATH} does not exist."
    with open(PIPELINE_LOG_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected_lines = [
        "[INFO] Processed 6 input rows.",
        "[INFO] Generated 14 long records.",
        "[INFO] Stratified sample size: 11."
    ]
    for line in expected_lines:
        assert line in content, f"Expected log line '{line}' not found in {PIPELINE_LOG_PATH}."


def make_case():
    token = secrets.token_hex(6)
    products = ["Prod" + token + suffix for suffix in ("A", "B", "C", "D", "E")]
    errors = ["E" + str(secrets.randbelow(800000) + 100000) for _ in range(4)]
    rows = [
        ["Z9", "R1", f"Mon: [{products[0]}] positive - none | Fri: [{products[1]}] negative - {errors[0]} | malformed entry"],
        ["A2", "R1", f"Tue: [{products[2]}] positive - none | Wed: [{products[3]}] positive - {errors[1]}"],
        ["B1", "R1", f"Sun: [{products[4]}] positive - {errors[2]}"],
        ["C3", "R2", f"Thu: [{products[0]}] neutral - none | Bad: [Oops] neutral none"],
        ["A1", "R2", f"Fri: [{products[1]}] neutral - {errors[3]} | Mon: [{products[2]}] negative - none"],
        ["D4", "R2", f"Tue: [{products[3]}] neutral - none"],
    ]
    return rows


def derive_expected(input_rows):
    pattern = re.compile(r"^([A-Za-z]+): \[([^\]]+)\] ([A-Za-z]+) - ([^\s|]+)$")
    long_rows = []
    for user_id, region, log_text in input_rows:
        for entry in log_text.split("|"):
            match = pattern.fullmatch(entry.strip())
            if match:
                day, product, sentiment, error = match.groups()
                long_rows.append([user_id, region, day, product, sentiment, error])

    strata = defaultdict(list)
    for row in long_rows:
        strata[(row[1], row[4])].append(row)
    sample_rows = []
    for records in strata.values():
        sample_rows.extend(sorted(records, key=lambda r: (r[0], r[2]))[:2])
    return long_rows, sample_rows


def run_and_check(executable):
    input_rows = make_case()
    expected_long, expected_sample = derive_expected(input_rows)

    with open(INPUT_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["UserID", "Region", "LogText"])
        writer.writerows(input_rows)

    for path in (LONG_FORMAT_PATH, SAMPLE_PATH, PIPELINE_LOG_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run([executable], check=True, timeout=15)

    long_header, long_rows = read_csv(LONG_FORMAT_PATH)
    sample_header, sample_rows = read_csv(SAMPLE_PATH)
    assert long_header == EXPECTED_HEADER
    assert sample_header == EXPECTED_HEADER
    assert sorted(long_rows) == sorted(expected_long)
    assert sorted(sample_rows) == sorted(expected_sample)

    with open(PIPELINE_LOG_PATH, "r", encoding="utf-8") as f:
        log_lines = f.read().splitlines()
    assert log_lines == [
        f"[INFO] Processed {len(input_rows)} input rows.",
        f"[INFO] Generated {len(expected_long)} long records.",
        f"[INFO] Stratified sample size: {len(expected_sample)}."
    ]


def test_program_artifacts_and_dynamic_execution():
    assert os.path.isfile(SOURCE_PATH), f"File {SOURCE_PATH} does not exist."
    assert os.path.isfile(BINARY_PATH), f"File {BINARY_PATH} does not exist."
    assert os.access(BINARY_PATH, os.X_OK), f"File {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {BINARY_PATH} is not a compiled ELF executable."

    subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-o", COMPILED_SOURCE_PATH],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()
    try:
        run_and_check(BINARY_PATH)
        run_and_check(COMPILED_SOURCE_PATH)
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
