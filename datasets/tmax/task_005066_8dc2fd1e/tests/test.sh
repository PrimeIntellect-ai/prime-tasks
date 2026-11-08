#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

LEGACY_CONFIGS_DIR = "/home/user/legacy_configs"
BACKUP_DIR = "/home/user/backup"
MANIFEST_FILE = os.path.join(BACKUP_DIR, "manifest.txt")

def test_backup_directory_exists():
    """Test that the backup directory was created."""
    assert os.path.isdir(BACKUP_DIR), f"Backup directory {BACKUP_DIR} does not exist."

def test_chunks_and_manifest():
    """Test that the chunks are correctly generated and the manifest is accurate."""
    # 1. Derive expected merged string from the source files
    assert os.path.isdir(LEGACY_CONFIGS_DIR), f"Source directory {LEGACY_CONFIGS_DIR} missing."

    ini_files = sorted([f for f in os.listdir(LEGACY_CONFIGS_DIR) if f.endswith(".ini")])
    assert len(ini_files) > 0, "No .ini files found in source directory."

    merged_bytes = b""
    for filename in ini_files:
        filepath = os.path.join(LEGACY_CONFIGS_DIR, filename)
        with open(filepath, "rb") as f:
            # Read UTF-16LE and convert to UTF-8
            content = f.read().decode("utf-16le").encode("utf-8")

        header = f"---FILE:{filename}---\n".encode("utf-8")
        merged_bytes += header + content

    # 2. Derive expected chunks
    chunk_size = 50
    expected_chunks = []
    for i in range(0, len(merged_bytes), chunk_size):
        expected_chunks.append(merged_bytes[i:i+chunk_size])

    # 3. Verify each chunk file exists and has correct content
    expected_manifest_lines = []
    for i, chunk_data in enumerate(expected_chunks):
        chunk_filename = f"chunk_{i:02d}"
        chunk_filepath = os.path.join(BACKUP_DIR, chunk_filename)

        assert os.path.isfile(chunk_filepath), f"Expected chunk file missing: {chunk_filepath}"

        with open(chunk_filepath, "rb") as f:
            actual_data = f.read()

        assert actual_data == chunk_data, f"Content mismatch in {chunk_filename}. Expected {len(chunk_data)} bytes, got {len(actual_data)} bytes."

        # Calculate expected hash for the manifest
        chunk_hash = hashlib.sha256(chunk_data).hexdigest()
        expected_manifest_lines.append(f"{chunk_filename} {chunk_hash}")

    # 4. Verify manifest file
    assert os.path.isfile(MANIFEST_FILE), f"Manifest file missing: {MANIFEST_FILE}"

    with open(MANIFEST_FILE, "r", encoding="utf-8") as f:
        actual_manifest_lines = [line.strip() for line in f.read().strip().splitlines() if line.strip()]

    assert actual_manifest_lines == expected_manifest_lines, "Manifest contents do not match the expected format or hashes."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
