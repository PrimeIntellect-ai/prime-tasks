#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_curated_list_exists():
    """Test that the curated_list.txt file exists."""
    path = "/home/user/curated_list.txt"
    assert os.path.exists(path), f"File {path} does not exist. The task requires saving the output to this file."
    assert os.path.isfile(path), f"Path {path} is not a regular file."

def test_curated_list_content():
    """Test that the curated_list.txt contains the correct filtered and sorted artifacts."""
    bin_path = "/home/user/artifacts.bin"
    output_path = "/home/user/curated_list.txt"

    assert os.path.exists(bin_path), f"Source file {bin_path} is missing."
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    # Derive expected content from the binary file
    with open(bin_path, "rb") as f:
        f.seek(4096)
        metadata_block = f.read(512)

    # Decode and clean
    text = metadata_block.decode("utf-16le", errors="ignore")
    text = text.replace("\0", "")

    # Filter and sort
    lines = text.splitlines()
    expected_lines = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if "OBSOLETE" in line or "REJECTED" in line:
            continue
        expected_lines.append(line)

    expected_lines.sort()

    # Read actual output
    with open(output_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        "The content of curated_list.txt does not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
