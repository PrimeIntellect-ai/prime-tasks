#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import tarfile


def test_recovered_pngs():
    recovered_dir = "/home/user/recovered_pngs"
    assert os.path.isdir(recovered_dir), f"Directory {recovered_dir} does not exist."

    files = set(os.listdir(recovered_dir))
    expected_files = {"image1.png", "image2.png"}

    assert files == expected_files, f"Expected exactly {expected_files} in {recovered_dir}, but found {files}."

    source_paths = {
        "image1.png": "/home/user/research_data/image1.dat",
        "image2.png": "/home/user/research_data/subdir1/image2.dat",
    }

    # Check magic bytes and verify that each result is a real copy of its source.
    for fname in expected_files:
        path = os.path.join(recovered_dir, fname)
        assert not os.path.islink(path), f"Recovered file {path} must be a copy, not a symlink."
        assert stat.S_ISREG(os.stat(path).st_mode), f"Recovered path {path} is not a regular file."
        with open(path, "rb") as f:
            recovered = f.read()
        magic = recovered[:8]
        assert magic == b"\x89\x50\x4E\x47\x0D\x0A\x1A\x0A", f"File {path} does not have valid PNG magic bytes."
        with open(source_paths[fname], "rb") as f:
            source = f.read()
        assert recovered == source, f"Recovered file {path} is not an exact copy of {source_paths[fname]}."


def test_clean_csvs():
    clean_dir = "/home/user/clean_csvs"
    assert os.path.isdir(clean_dir), f"Directory {clean_dir} does not exist."

    files = set(os.listdir(clean_dir))
    expected_files = {"recent1.csv"}

    assert files == expected_files, f"Expected exactly {expected_files} in {clean_dir}, but found {files}."

    # Check encoding and content.
    recent_csv = os.path.join(clean_dir, "recent1.csv")
    assert not os.path.islink(recent_csv), f"Converted file {recent_csv} must not be a symlink."
    assert stat.S_ISREG(os.stat(recent_csv).st_mode), f"Converted path {recent_csv} is not a regular file."
    try:
        with open(recent_csv, "r", encoding="utf-8") as f:
            content = f.read()
            assert "René" in content, f"Expected string 'René' not found in {recent_csv}."
    except UnicodeDecodeError:
        assert False, f"File {recent_csv} is not properly UTF-8 encoded."

    # Derive the complete expected UTF-8 output from the WINDOWS-1252 source.
    source_csv = "/home/user/research_data/recent1.csv"
    with open(source_csv, "rb") as f:
        expected_bytes = f.read().decode("cp1252").encode("utf-8")
    with open(recent_csv, "rb") as f:
        actual_bytes = f.read()
    assert actual_bytes == expected_bytes, f"File {recent_csv} is not the complete UTF-8 conversion of {source_csv}."


def test_bad_archives_log():
    log_file = "/home/user/bad_archives.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = {
        "/home/user/research_data/bad1.tar.gz",
        "/home/user/research_data/subdir1/bad2.tar.gz"
    }

    assert set(lines) == expected_lines, f"Expected {expected_lines} in {log_file}, but found {set(lines)}."
    assert len(lines) == 2, f"Expected exactly 2 lines in {log_file}, but found {len(lines)}."


def test_no_infinite_loop_artifacts():
    # Ensure no files were copied from following the infinite loop.
    loop_dir = "/home/user/research_data/infinite_loop"
    if os.path.islink(loop_dir):
        # Exact file count checks in the previous tests enforce this.
        pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
