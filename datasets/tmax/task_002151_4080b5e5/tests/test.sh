#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_symlink_latest_backup():
    symlink_path = "/home/user/latest_backup"
    expected_target = "/home/user/data/inc"

    assert os.path.exists(symlink_path), f"Symlink {symlink_path} does not exist."
    assert os.path.islink(symlink_path), f"Path {symlink_path} exists but is not a symbolic link."

    target = os.readlink(symlink_path)
    assert target == expected_target, f"Symlink {symlink_path} points to '{target}', expected '{expected_target}'."

def test_base_contents_are_unchanged():
    base_dir = "/home/user/data/base"
    expected_contents = {
        "file1.txt": b"abc",
        "file2.txt": b"defg",
        "file3.txt": b"hi",
        "file5.txt": b"jklmnop",
    }

    for filename, expected in expected_contents.items():
        path = os.path.join(base_dir, filename)
        assert os.path.isfile(path), f"Base file missing or not a regular file: {path}"
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"Base file contents were modified: {path}"

def test_hardlinks_created_correctly():
    base_dir = "/home/user/data/base"
    inc_dir = "/home/user/data/inc"

    # Verify file1.txt
    base_file1 = os.path.join(base_dir, "file1.txt")
    inc_file1 = os.path.join(inc_dir, "file1.txt")
    assert os.path.exists(base_file1), f"Base file missing: {base_file1}"
    assert os.path.exists(inc_file1), f"Incremental file missing: {inc_file1}"
    assert os.stat(base_file1).st_ino == os.stat(inc_file1).st_ino, "file1.txt was not deduplicated (inodes differ)."
    with open(inc_file1, "rb") as f:
        assert f.read() == b"abc", "Deduplicated file1.txt does not contain its original data."

    # Verify file5.txt
    base_file5 = os.path.join(base_dir, "file5.txt")
    inc_file5 = os.path.join(inc_dir, "file5.txt")
    assert os.path.exists(base_file5), f"Base file missing: {base_file5}"
    assert os.path.exists(inc_file5), f"Incremental file missing: {inc_file5}"
    assert os.stat(base_file5).st_ino == os.stat(inc_file5).st_ino, "file5.txt was not deduplicated (inodes differ)."
    with open(inc_file5, "rb") as f:
        assert f.read() == b"jklmnop", "Deduplicated file5.txt does not contain its original data."

    # Verify file2.txt (should NOT be hardlinked as contents differ)
    base_file2 = os.path.join(base_dir, "file2.txt")
    inc_file2 = os.path.join(inc_dir, "file2.txt")
    assert os.path.exists(base_file2), f"Base file missing: {base_file2}"
    assert os.path.exists(inc_file2), f"Incremental file missing: {inc_file2}"
    assert os.stat(base_file2).st_ino != os.stat(inc_file2).st_ino, "file2.txt was incorrectly deduplicated (inodes are the same, but contents were different)."

def test_csv_report():
    report_path = "/home/user/dedup_report.csv"
    assert os.path.isfile(report_path), f"CSV report {report_path} is missing."

    with open(report_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) >= 1, "CSV report is empty."

    header = rows[0]
    assert header == ["filename", "saved_bytes"], f"CSV header is incorrect. Expected ['filename', 'saved_bytes'], got {header}."

    data_rows = rows[1:]
    assert len(data_rows) == 2, f"Expected exactly 2 data rows in CSV, found {len(data_rows)}."

    # Sort the rows to make the test order-independent
    data_rows.sort(key=lambda x: x[0])
    expected_rows = [["file1.txt", "3"], ["file5.txt", "7"]]

    assert data_rows == expected_rows, f"CSV data rows are incorrect. Expected {expected_rows}, got {data_rows}."

    actual_size_rows = [
        ["file1.txt", str(os.path.getsize("/home/user/data/inc/file1.txt"))],
        ["file5.txt", str(os.path.getsize("/home/user/data/inc/file5.txt"))],
    ]
    assert data_rows == actual_size_rows, f"CSV saved_bytes values do not match the deduplicated files: {actual_size_rows}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
