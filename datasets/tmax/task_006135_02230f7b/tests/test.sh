#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import gzip
import csv
import glob
import random
import math
from collections import Counter
import pytest

BACKUP_DIR = "/home/user/clean_backups"
MANIFEST_PATH = os.path.join(BACKUP_DIR, "manifest.json")
EXPECTED_HEADER = ["timestamp", "server_id", "metric_value", "status"]


def generate_expected_rows():
    """Independently reproduce the deterministic source data from setup."""
    random.seed(42)
    rows = []

    for count in (600, 400, 200):
        for _ in range(count):
            timestamp = str(random.randint(1600000000, 1700000000))
            server_id = f"srv_{random.randint(1, 10)}"
            metric_value = str(random.randint(-50, 200))
            status = random.choice(["OK", "ERROR", "WARN", "DEBUG"])

            if status != "DEBUG" and float(metric_value) >= 0:
                rows.append((timestamp, server_id, metric_value, status))

    return rows


EXPECTED_ROWS = generate_expected_rows()
EXPECTED_FILES = ["file1.csv", "file2.csv", "file3.csv"]


def test_manifest_exists_and_correct():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file not found at {MANIFEST_PATH}"

    with open(MANIFEST_PATH, "r") as f:
        try:
            manifest_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest file is not valid JSON.")

    assert "processed_files" in manifest_data, "Manifest missing 'processed_files' key."

    expected_files = ["file1.csv", "file2.csv", "file3.csv"]
    actual_files = manifest_data["processed_files"]

    assert sorted(actual_files) == expected_files, f"Expected processed_files to be {expected_files}, got {actual_files}"


def test_backup_files_exist_and_valid():
    assert os.path.exists(BACKUP_DIR), f"Backup directory not found at {BACKUP_DIR}"

    backup_files = sorted(glob.glob(os.path.join(BACKUP_DIR, "backup_part_*.csv.gz")))
    assert len(backup_files) > 0, "No backup files found matching backup_part_*.csv.gz"

    previous_timestamp = None
    expected_header = ["timestamp", "server_id", "metric_value", "status"]

    for i, file_path in enumerate(backup_files):
        expected_filename = f"backup_part_{i+1:03d}.csv.gz"
        assert os.path.basename(file_path) == expected_filename, f"Expected filename {expected_filename}, got {os.path.basename(file_path)}"

        with gzip.open(file_path, "rt", newline="") as f:
            reader = csv.reader(f)

            try:
                header = next(reader)
            except StopIteration:
                pytest.fail(f"File {file_path} is empty.")

            assert header == expected_header, f"File {file_path} has incorrect header. Expected {expected_header}, got {header}"

            row_count = 0
            for row in reader:
                row_count += 1

                assert len(row) == 4, f"File {file_path} has a row with incorrect number of columns: {row}"

                timestamp_str, server_id, metric_value_str, status = row

                assert status != "DEBUG", f"Found 'DEBUG' status in {file_path}, row: {row}"

                try:
                    metric_value = float(metric_value_str)
                    assert metric_value >= 0, f"Found negative metric value in {file_path}, row: {row}"
                except ValueError:
                    pytest.fail(f"Invalid metric value '{metric_value_str}' in {file_path}")

                if previous_timestamp is not None:
                    assert timestamp_str >= previous_timestamp, f"Data is not sorted correctly globally. Found timestamp {timestamp_str} after {previous_timestamp} in {file_path}"
                previous_timestamp = timestamp_str

            assert row_count <= 500, f"File {file_path} exceeds 500 data rows (found {row_count})"
            if i < len(backup_files) - 1:
                assert row_count == 500, f"File {file_path} is not the last file but has {row_count} data rows instead of 500"


def test_backup_content_is_complete_and_exact():
    backup_files = sorted(glob.glob(os.path.join(BACKUP_DIR, "backup_part_*.csv.gz")))
    expected_part_count = math.ceil(len(EXPECTED_ROWS) / 500)
    assert len(backup_files) == expected_part_count, (
        f"Expected {expected_part_count} backup parts for {len(EXPECTED_ROWS)} rows, "
        f"found {len(backup_files)}"
    )

    actual_rows = []
    part_sizes = []
    for file_path in backup_files:
        with gzip.open(file_path, "rt", newline="") as f:
            reader = csv.reader(f)
            header = next(reader, None)
            assert header == EXPECTED_HEADER
            part_rows = [tuple(row) for row in reader]
            part_sizes.append(len(part_rows))
            actual_rows.extend(part_rows)

    expected_sizes = [
        min(500, len(EXPECTED_ROWS) - offset)
        for offset in range(0, len(EXPECTED_ROWS), 500)
    ]
    assert part_sizes == expected_sizes, f"Expected chunk sizes {expected_sizes}, got {part_sizes}"
    assert len(actual_rows) == len(EXPECTED_ROWS), (
        f"Expected {len(EXPECTED_ROWS)} filtered rows, got {len(actual_rows)}"
    )
    assert Counter(actual_rows) == Counter(EXPECTED_ROWS), (
        "Backup rows do not exactly match the independently derived filtered source rows"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
