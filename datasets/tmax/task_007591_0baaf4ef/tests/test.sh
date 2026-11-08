#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

EXPORT_DIR = "/home/user/export_data"
MANIFEST_FILE = "/home/user/manifest.txt"
PROJECT_DATA_DIR = "/home/user/project_data"

def get_expected_concatenated_data():
    # Find all CSV files and sort them alphabetically by path
    csv_files = []
    for root, _, files in os.walk(PROJECT_DATA_DIR):
        for file in files:
            if file.endswith('.csv'):
                csv_files.append(os.path.join(root, file))

    csv_files.sort()

    concatenated_lines = []
    for file in csv_files:
        with open(file, 'r') as f:
            concatenated_lines.extend(f.readlines())

    return concatenated_lines

def test_export_directory_exists():
    assert os.path.isdir(EXPORT_DIR), f"Directory {EXPORT_DIR} does not exist."

def test_split_files_exist_and_correct_lines():
    expected_data = get_expected_concatenated_data()

    # Expected chunks
    chunks = [
        expected_data[0:50],
        expected_data[50:100],
        expected_data[100:115]
    ]

    for i, chunk in enumerate(chunks):
        part_filename = f"part_{i:02d}"
        part_filepath = os.path.join(EXPORT_DIR, part_filename)

        assert os.path.isfile(part_filepath), f"Split file {part_filepath} does not exist."

        with open(part_filepath, 'r') as f:
            lines = f.readlines()

        assert len(lines) == len(chunk), f"File {part_filename} has {len(lines)} lines, expected {len(chunk)}."
        assert lines == chunk, f"Contents of {part_filename} do not match the expected concatenated data."

def test_manifest_file_exists_and_correct():
    assert os.path.isfile(MANIFEST_FILE), f"Manifest file {MANIFEST_FILE} does not exist."

    expected_manifest_lines = []

    for i in range(3):
        part_filename = f"part_{i:02d}"
        part_filepath = os.path.join(EXPORT_DIR, part_filename)

        if os.path.isfile(part_filepath):
            with open(part_filepath, 'rb') as f:
                file_hash = hashlib.sha256(f.read()).hexdigest()
            # The format of sha256sum output is "hash  filename"
            expected_manifest_lines.append(f"{file_hash}  {part_filename}\n")

    expected_manifest_lines.sort()

    with open(MANIFEST_FILE, 'r') as f:
        actual_manifest_lines = f.readlines()

    actual_manifest_lines.sort()

    assert actual_manifest_lines == expected_manifest_lines, "Manifest file contents do not match expected hashes and filenames."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
