#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import csv
import hashlib
import os
import pytest

MANIFEST_PATH = "/home/user/manifest.csv"

def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def test_manifest_exists():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."
    assert os.path.isfile(MANIFEST_PATH), f"{MANIFEST_PATH} is not a file."

def test_manifest_content():
    with open(MANIFEST_PATH, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["Filepath", "Archive-ID", "SHA256", "Status"], "CSV header is incorrect."

        rows = list(reader)
        assert len(rows) == 4, f"Expected 4 rows of data, found {len(rows)}."

        expected_files = [
            "/home/user/backup_vault/db/backup1.zip",
            "/home/user/backup_vault/db/backup2.zip",
            "/home/user/backup_vault/logs/2022/authlog.tar.gz",
            "/home/user/backup_vault/logs/2022/syslog.tar.gz"
        ]

        for i, row in enumerate(rows):
            assert len(row) == 4, f"Row {i+1} does not have exactly 4 columns: {row}"
            filepath, archive_id, sha256_val, status = row

            assert filepath == expected_files[i], f"Expected filepath {expected_files[i]} at row {i+1}, but got {filepath}. Make sure rows are sorted alphabetically by Filepath."

            actual_sha = get_sha256(filepath)
            assert sha256_val == actual_sha, f"SHA256 mismatch for {filepath}. Expected {actual_sha}, got {sha256_val}."

            if "backup1.zip" in filepath:
                assert status == "VALID", f"Status for {filepath} should be VALID."
                assert archive_id == "DB-1001", f"Archive-ID for {filepath} should be DB-1001."
            elif "syslog.tar.gz" in filepath:
                assert status == "VALID", f"Status for {filepath} should be VALID."
                assert archive_id == "LOG-8888", f"Archive-ID for {filepath} should be LOG-8888."
            else:
                assert status == "CORRUPT", f"Status for {filepath} should be CORRUPT."
                assert archive_id == "UNKNOWN", f"Archive-ID for {filepath} should be UNKNOWN."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
