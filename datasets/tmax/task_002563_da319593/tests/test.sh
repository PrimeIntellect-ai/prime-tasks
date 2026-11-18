#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

def test_final_state():
    processed_dir = "/home/user/processed"
    final_inventory = "/home/user/final_inventory.txt"

    # 1. Check extraction directory exists
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} does not exist."

    # 2. Check symlinks are deleted
    for root, dirs, files in os.walk(processed_dir):
        for name in dirs + files:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f"Symlink found at {path}, which should have been deleted."

    # 3. Check specific files exist and are correctly renamed
    expected_files = {
        "cafe_log_1.txt": "Café observation data: 42",
        "group_notes_2.txt": "München research group notes"
    }

    found_txt_files = []
    for root, dirs, files in os.walk(processed_dir):
        for file in files:
            if file.endswith(".txt"):
                found_txt_files.append(os.path.join(root, file))

    assert len(found_txt_files) == 2, f"Expected exactly 2 .txt files, found {len(found_txt_files)}."

    for expected_name, expected_content in expected_files.items():
        expected_path = os.path.join(processed_dir, expected_name)
        assert os.path.isfile(expected_path), f"Expected file {expected_path} not found. Ensure files were renamed properly."

        # Check UTF-8 encoding and content
        try:
            with open(expected_path, "r", encoding="utf-8") as f:
                content = f.read()
            assert content == expected_content, f"Content of {expected_path} does not match expected UTF-8 content."
        except UnicodeDecodeError:
            pytest.fail(f"File {expected_path} is not valid UTF-8.")

    # 4. Check final_inventory.txt exists and has correct format and content
    assert os.path.isfile(final_inventory), f"Final inventory file {final_inventory} does not exist."

    expected_lines = []
    for expected_name, expected_content in expected_files.items():
        expected_path = os.path.join(processed_dir, expected_name)
        file_hash = hashlib.sha256(expected_content.encode('utf-8')).hexdigest()
        expected_lines.append(f"{file_hash}  {expected_path}")

    expected_lines.sort()

    with open(final_inventory, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {final_inventory} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
