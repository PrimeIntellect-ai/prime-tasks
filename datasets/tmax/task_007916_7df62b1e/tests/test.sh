#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

def test_malicious_archive_txt():
    target_file = '/home/user/malicious_archive.txt'
    assert os.path.exists(target_file), f"File {target_file} does not exist."

    with open(target_file, 'r') as f:
        content = f.read().strip()

    assert content == 'backup_03.zip', f"Expected 'backup_03.zip' in {target_file}, but got '{content}'."

def test_malicious_payload_files_txt():
    target_file = '/home/user/malicious_payload_files.txt'
    assert os.path.exists(target_file), f"File {target_file} does not exist."

    with open(target_file, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = {
        'docs/readme.txt',
        '../../../home/user/.ssh/authorized_keys'
    }

    assert set(lines) == expected_lines, f"Expected lines {expected_lines} in {target_file}, but got {set(lines)}."

def test_safe_backups_sha256():
    target_file = '/home/user/safe_backups.sha256'
    assert os.path.exists(target_file), f"File {target_file} does not exist."

    safe_backups = ['backup_01.zip', 'backup_02.zip', 'backup_04.zip']
    expected_hashes = {}

    base_dir = '/home/user/backups'
    for backup in safe_backups:
        path = os.path.join(base_dir, backup)
        assert os.path.exists(path), f"Expected safe backup {path} is missing."

        sha256 = hashlib.sha256()
        with open(path, 'rb') as f:
            sha256.update(f.read())
        expected_hashes[backup] = sha256.hexdigest()

    with open(target_file, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    actual_hashes = {}
    for line in lines:
        parts = line.split()
        if len(parts) >= 2:
            h = parts[0]
            # Handle potential '*' or ' ' before filename in sha256sum output
            fname = parts[1].lstrip('*')
            actual_hashes[fname] = h

    for backup in safe_backups:
        assert backup in actual_hashes, f"Missing checksum for {backup} in {target_file}."
        assert actual_hashes[backup] == expected_hashes[backup], f"Incorrect hash for {backup}. Expected {expected_hashes[backup]}, got {actual_hashes[backup]}."

    assert len(actual_hashes) == len(safe_backups), f"Expected exactly {len(safe_backups)} entries in {target_file}, but found {len(actual_hashes)}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
