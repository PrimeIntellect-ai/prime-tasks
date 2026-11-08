#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import glob
import pytest

def encode_rle(text: str) -> str:
    if not text:
        return ""
    result = []
    current_char = text[0]
    count = 1
    for char in text[1:]:
        if char == current_char:
            count += 1
        else:
            result.append(f"{current_char}{count}")
            current_char = char
            count = 1
    result.append(f"{current_char}{count}")
    return "".join(result)

def test_archive_rle_exists_and_correct():
    raw_dir = "/home/user/backups/raw"
    archive_file = "/home/user/backups/archive.rle"

    assert os.path.isdir(raw_dir), f"Directory {raw_dir} is missing."
    assert os.path.isfile(archive_file), f"Archive file {archive_file} was not created."

    # Read and parse all json files
    users = []
    for filepath in glob.glob(os.path.join(raw_dir, "*.json")):
        with open(filepath, "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
                if "id" in data and "name" in data and "email" in data:
                    users.append(data)
            except json.JSONDecodeError:
                pass

    # Sort by id
    users.sort(key=lambda x: int(x["id"]))

    # Build CSV string
    csv_lines = ["id,name,email"]
    for user in users:
        csv_lines.append(f'{user["id"]},{user["name"]},[REDACTED]')

    csv_string = "\n".join(csv_lines) + "\n"

    # Compute RLE
    expected_rle = encode_rle(csv_string)

    # Read actual
    with open(archive_file, "r", encoding="utf-8") as f:
        actual_rle = f.read()

    assert actual_rle == expected_rle, (
        f"The content of {archive_file} does not match the expected RLE encoding.\n"
        f"Expected:\n{repr(expected_rle)}\n"
        f"Actual:\n{repr(actual_rle)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
