#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import pytest

ARCHIVE_DIR = "/home/user/archive"
LOG_FILE = "/home/user/app_logs.txt"
METADATA_FILE = "/home/user/server_metadata.json"


def parse_expected_records():
    with open(METADATA_FILE, "r", encoding="utf-8") as f:
        metadata = json.load(f)

    records = []
    current = None

    with open(LOG_FILE, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.rstrip("\r\n")

            if line == "[START_ENTRY]":
                assert current is None, "Nested [START_ENTRY] found in input log."
                current = {}
            elif line == "[END_ENTRY]":
                assert current is not None, "[END_ENTRY] found without [START_ENTRY]."
                for key in ["Timestamp", "Level", "ServerID", "Message"]:
                    assert key in current, f"Input entry is missing required key: {key}"

                if current["Level"] in ["ERROR", "CRITICAL"]:
                    records.append([
                        current["Timestamp"],
                        current["Level"],
                        metadata.get(current["ServerID"], "UNKNOWN"),
                        current["Message"],
                    ])
                current = None
            elif current is not None and ": " in line:
                key, value = line.split(": ", 1)
                current[key] = value

    assert current is None, "Input log contains an unterminated entry."
    return records


def read_archive_records():
    records = []
    for filename in ["archive_001.csv", "archive_002.csv", "archive_003.csv"]:
        filepath = os.path.join(ARCHIVE_DIR, filename)
        with open(filepath, "r", newline="", encoding="utf-8") as f:
            reader = csv.reader(f)
            next(reader, None)
            records.extend(list(reader))
    return records


def test_archive_directory_exists():
    assert os.path.exists(ARCHIVE_DIR), f"Directory missing: {ARCHIVE_DIR}"
    assert os.path.isdir(ARCHIVE_DIR), f"Expected a directory, found something else: {ARCHIVE_DIR}"


def test_archive_files_exist_and_counts():
    file_001 = os.path.join(ARCHIVE_DIR, "archive_001.csv")
    file_002 = os.path.join(ARCHIVE_DIR, "archive_002.csv")
    file_003 = os.path.join(ARCHIVE_DIR, "archive_003.csv")
    file_004 = os.path.join(ARCHIVE_DIR, "archive_004.csv")

    assert os.path.exists(file_001), "archive_001.csv is missing."
    assert os.path.exists(file_002), "archive_002.csv is missing."
    assert os.path.exists(file_003), "archive_003.csv is missing."
    assert not os.path.exists(file_004), "archive_004.csv should not exist."


def test_csv_headers_and_content():
    expected_header = ["Timestamp", "Level", "ServerName", "Message"]

    files_to_check = [
        ("archive_001.csv", 50),
        ("archive_002.csv", 50),
        ("archive_003.csv", 15),
    ]

    total_records = 0

    for filename, expected_count in files_to_check:
        filepath = os.path.join(ARCHIVE_DIR, filename)
        assert os.path.exists(filepath), f"{filename} is missing."

        with open(filepath, "r", newline="", encoding="utf-8") as f:
            reader = csv.reader(f)
            header = next(reader, None)
            assert header == expected_header, f"Header in {filename} does not match expected. Got: {header}"

            row_count = 0
            for row in reader:
                assert len(row) == 4, f"Row in {filename} does not have exactly 4 columns: {row}"

                level = row[1]
                server_name = row[2]

                assert level in ["ERROR", "CRITICAL"], f"Invalid level '{level}' found in {filename}."
                assert server_name != "S4", f"Raw ServerID 'S4' found in {filename}, should be 'UNKNOWN'."
                if server_name not in ["Alpha_Node", "Beta_Node", "Gamma_Node"]:
                    assert server_name == "UNKNOWN", f"Unexpected ServerName '{server_name}' found in {filename}."

                row_count += 1
                total_records += 1

            assert row_count == expected_count, f"Expected {expected_count} records in {filename}, got {row_count}."

    assert total_records == 115, f"Expected exactly 115 error/critical records total, got {total_records}."


def test_records_match_source_logs_exactly():
    expected = parse_expected_records()
    actual = read_archive_records()

    assert len(expected) == 115, f"Expected source log to contain 115 error/critical records, got {len(expected)}."
    assert actual == expected, "Archived rows do not exactly match the filtered, enriched source records in input order."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
