#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import pytest

def test_unsafe_paths_log():
    log_path = "/home/user/unsafe_paths.log"
    assert os.path.exists(log_path), f"The file {log_path} does not exist."
    assert os.path.isfile(log_path), f"The path {log_path} is not a file."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_unsafe = [
        "../etc/shadow.bak",
        "/var/www/html/backdoor.php",
        "docs/../../var/tmp/bad.sh"
    ]
    expected_unsafe.sort()

    assert lines == expected_unsafe, f"The contents of {log_path} do not match the expected sorted unsafe paths. Found: {lines}"

def test_safe_extraction():
    extract_dir = "/home/user/safe_extraction"
    assert os.path.exists(extract_dir), f"The directory {extract_dir} does not exist."
    assert os.path.isdir(extract_dir), f"The path {extract_dir} is not a directory."

    # Get all files in the extraction directory
    extracted_files = []
    for root, _, files in os.walk(extract_dir):
        for file in files:
            rel_path = os.path.relpath(os.path.join(root, file), extract_dir)
            extracted_files.append(rel_path)

    expected_files = [
        "docs/readme.txt",
        "docs/info.txt",
        "logs/system.log",
        "logs/app.log",
        "src/main.c"
    ]

    # Normalize expected paths (some might have been extracted with normalized paths if tar stripped them, but usually they match logical paths)
    normalized_extracted = [os.path.normpath(p) for p in extracted_files]
    normalized_expected = [os.path.normpath(p) for p in expected_files]

    normalized_extracted.sort()
    normalized_expected.sort()

    assert normalized_extracted == normalized_expected, f"The extracted files in {extract_dir} do not match the expected safe files. Found: {normalized_extracted}"

def test_error_summary():
    summary_path = "/home/user/error_summary.txt"
    assert os.path.exists(summary_path), f"The file {summary_path} does not exist."
    assert os.path.isfile(summary_path), f"The path {summary_path} is not a file."

    with open(summary_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_errors = [
        "ERROR: memory leak detected",
        "ERROR: null pointer exception"
    ]

    lines.sort()
    expected_errors.sort()

    assert lines == expected_errors, f"The contents of {summary_path} do not match the expected ERROR lines. Found: {lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
