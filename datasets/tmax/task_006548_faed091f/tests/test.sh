#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import gzip
import pytest

def test_json_file_exists_and_content():
    json_path = "/home/user/recent_index.json"
    assert os.path.exists(json_path), f"File {json_path} does not exist."
    assert os.path.isfile(json_path), f"Path {json_path} is not a file."

    with open(json_path, 'r', encoding='utf-8') as f:
        raw_content = f.read()

    try:
        data = json.loads(raw_content)
    except json.JSONDecodeError:
        pytest.fail(f"File {json_path} does not contain valid JSON.")

    expected_data = {
        "/home/user/docs_root/intro.md": "\\n\\n# Welcome to docs",
        "/home/user/docs_root/dir1/setup.md": "# Setup Instructions\\nStep 1",
        "/home/user/docs_root/dir2/config.md": "# Configuration\\nPort 8080"
    }

    assert data == expected_data, f"JSON content does not match expected output. Got: {data}"

    # Check formatting (4 spaces indentation)
    expected_formatted = json.dumps(data, indent=4)
    # The student's script might have different ordering of keys, so we check if the file has 4 spaces indentation.
    # We can do this by checking if the dumped version with the same keys matches (ignoring trailing newlines)
    # Or simply check if it parses, but the prompt says: "formatted JSON file (with 4 spaces indentation)"
    # We can check if lines start with 4 spaces.
    lines = raw_content.strip().split('\n')
    if len(lines) > 2:
        assert lines[1].startswith("    ") and not lines[1].startswith("     "), "JSON file does not appear to be indented with exactly 4 spaces."

def test_gzip_file_exists_and_content():
    json_path = "/home/user/recent_index.json"
    gz_path = "/home/user/recent_index.json.gz"

    assert os.path.exists(gz_path), f"File {gz_path} does not exist."
    assert os.path.isfile(gz_path), f"Path {gz_path} is not a file."

    with open(json_path, 'rb') as f:
        expected_bytes = f.read()

    try:
        with gzip.open(gz_path, 'rb') as gz_file:
            decompressed_bytes = gz_file.read()
    except Exception as e:
        pytest.fail(f"Failed to decompress {gz_path}: {e}")

    assert decompressed_bytes == expected_bytes, f"Decompressed content of {gz_path} does not match {json_path} exactly."

def test_script_exists():
    script_path = "/home/user/index_docs.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
