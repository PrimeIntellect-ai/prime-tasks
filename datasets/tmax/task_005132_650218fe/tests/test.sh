#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import zlib
import pytest

EXPECTED_FILES = {
    "alpha_sensor": b'ALPHA_DATA_START ' + b'01010101'*1000 + b' END',
    "beta_sensor": b'BETA_DATA_START ' + b'10101010'*1500 + b' END',
    "gamma_sensor": b'GAMMA_DATA_START ' + b'11223344'*2000 + b' END'
}

RAW_DATA_DIR = "/home/user/raw_data"
ARCHIVE_DIR = "/home/user/archive"
REPORT_PATH = "/home/user/space_report.csv"

def test_symlinks_and_targets():
    for f_base, original_content in EXPECTED_FILES.items():
        symlink_path = os.path.join(RAW_DATA_DIR, f"{f_base}.dat")
        target_path = os.path.join(ARCHIVE_DIR, f"{f_base}.zdat")

        # Check that the symlink exists
        assert os.path.islink(symlink_path), f"File {symlink_path} is not a symbolic link."

        # Check that the symlink points to the correct absolute path
        actual_target = os.readlink(symlink_path)
        assert actual_target == target_path, f"Symlink {symlink_path} points to {actual_target}, expected {target_path}."

        # Check that the target file exists
        assert os.path.isfile(target_path), f"Compressed file {target_path} does not exist."

def test_compressed_data():
    for f_base, original_content in EXPECTED_FILES.items():
        target_path = os.path.join(ARCHIVE_DIR, f"{f_base}.zdat")
        assert os.path.isfile(target_path), f"Compressed file {target_path} is missing."

        with open(target_path, 'rb') as zf:
            compressed_data = zf.read()

        try:
            decompressed_data = zlib.decompress(compressed_data)
        except zlib.error as e:
            pytest.fail(f"File {target_path} is not valid zlib compressed data: {e}")

        assert decompressed_data == original_content, f"Decompressed content of {target_path} does not match original data."

def test_space_report():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."

    expected_lines = []
    for f_base in sorted(EXPECTED_FILES.keys()):
        symlink_path = os.path.join(RAW_DATA_DIR, f"{f_base}.dat")
        target_path = os.path.join(ARCHIVE_DIR, f"{f_base}.zdat")
        expected_lines.append(f"{symlink_path},{target_path}")

    with open(REPORT_PATH, 'r') as r:
        content = r.read().strip()

    assert content, f"Report file {REPORT_PATH} is empty."
    lines = content.split('\n')

    assert len(lines) == len(expected_lines), f"Report file has {len(lines)} lines, expected {len(expected_lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in report is incorrect. Expected: '{expected}', Got: '{actual}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
