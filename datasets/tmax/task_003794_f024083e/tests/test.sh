#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_scanner_go_exists():
    """Verify that the student's Go program exists."""
    assert os.path.isfile("/home/user/scanner.go"), "The Go program /home/user/scanner.go was not found."

def test_report_csv_contents():
    """Verify that the CSV report was generated correctly with the correct format and sorted entries."""
    report_path = "/home/user/report.csv"
    assert os.path.isfile(report_path), f"The report file {report_path} was not generated."

    base_dir = "/home/user/storage_dump"
    expected_entries = []
    seen_inodes = set()

    # Walk without following links to avoid infinite loops, but resolve files to find all unique targets
    for root, dirs, files in os.walk(base_dir, followlinks=False):
        for f in files:
            full_path = os.path.join(root, f)

            # Resolve symlinks to their real path
            if os.path.islink(full_path):
                full_path = os.path.realpath(full_path)

            if not os.path.exists(full_path) or not os.path.isfile(full_path):
                continue

            st = os.stat(full_path)
            if st.st_ino in seen_inodes:
                continue
            seen_inodes.add(st.st_ino)

            try:
                with open(full_path, "rb") as fp:
                    header = fp.read(4)
            except OSError:
                continue

            if header == b"\x7FELF":
                expected_entries.append((st.st_ino, "ELF", st.st_size))
            elif header == b"; G-":
                expected_entries.append((st.st_ino, "GCODE", st.st_size))

    # Sort by inode in ascending order
    expected_entries.sort(key=lambda x: x[0])
    expected_lines = [f"{ino},{typ},{size}" for ino, typ, size in expected_entries]

    with open(report_path, "r") as fp:
        actual_lines = [line.strip() for line in fp if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of {report_path} do not match the expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
