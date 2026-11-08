#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib

BACKUPS_DIR = "/home/user/backups"
MANIFEST_PATH = "/home/user/valid_logs_manifest.txt"

EXPECTED_LOGS = {
    "app_a.log": (
        "System initialized.\n"
        "Connecting to [ARCHIVE_NODE_01] for block storage...\n"
        "[ARCHIVE_NODE_01] connected successfully.\n"
        "Transferring 500MB.\n"
    ),
    "app_b.log": (
        "Warning: High latency detected.\n"
        "[ARCHIVE_NODE_01] timeout waiting for flush.\n"
        "Retry 1... [ARCHIVE_NODE_01] responded.\n"
    ),
    "app_c.log": (
        "Normal operations.\n"
        "No storage nodes contacted.\n"
    )
}

def test_no_gz_files_remain():
    """Ensure all .gz files (valid and corrupt) have been deleted."""
    assert os.path.isdir(BACKUPS_DIR), f"Directory {BACKUPS_DIR} is missing."
    files = os.listdir(BACKUPS_DIR)
    gz_files = [f for f in files if f.endswith(".gz")]
    assert not gz_files, f"Found remaining .gz files in backups directory: {gz_files}"

def test_extracted_logs_exist_and_correct():
    """Ensure only the expected .log files exist and have the correct sanitized content."""
    assert os.path.isdir(BACKUPS_DIR), f"Directory {BACKUPS_DIR} is missing."
    files = os.listdir(BACKUPS_DIR)

    # Check that exactly the expected log files are present
    log_files = [f for f in files if f.endswith(".log")]
    expected_filenames = set(EXPECTED_LOGS.keys())

    assert set(log_files) == expected_filenames, (
        f"Expected log files {expected_filenames}, but found {set(log_files)}"
    )

    # Check contents
    for filename, expected_content in EXPECTED_LOGS.items():
        filepath = os.path.join(BACKUPS_DIR, filename)
        with open(filepath, "r") as f:
            content = f.read()

        assert content == expected_content, (
            f"Content of {filename} does not match expected sanitized output.\n"
            f"Expected:\n{expected_content}\nActual:\n{content}"
        )

def test_manifest_correctness():
    """Ensure the manifest file exists, is correctly formatted, and has valid SHA256 hashes."""
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"

    # Compute expected manifest lines based on actual expected content
    expected_lines = []
    for filename in sorted(EXPECTED_LOGS.keys()):
        filepath = os.path.join(BACKUPS_DIR, filename)
        content = EXPECTED_LOGS[filename].encode('utf-8')
        file_hash = hashlib.sha256(content).hexdigest()
        expected_lines.append(f"{file_hash}  {filepath}")

    with open(MANIFEST_PATH, "r") as f:
        manifest_content = f.read().strip().splitlines()

    assert len(manifest_content) == len(expected_lines), (
        f"Manifest should have exactly {len(expected_lines)} lines, found {len(manifest_content)}."
    )

    for i, (actual_line, expected_line) in enumerate(zip(manifest_content, expected_lines)):
        assert actual_line.strip() == expected_line, (
            f"Manifest line {i+1} is incorrect.\n"
            f"Expected: '{expected_line}'\n"
            f"Actual:   '{actual_line.strip()}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
