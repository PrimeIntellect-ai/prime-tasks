#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_output_file_exists():
    """Test that the output JSON file exists."""
    output_path = "/home/user/top_5_hogs.json"
    assert os.path.exists(output_path), f"Output file not found at {output_path}"
    assert os.path.isfile(output_path), f"Path {output_path} is not a file"

def test_output_file_contents():
    """Test that the output JSON file contains the correct top 5 largest files."""
    output_path = "/home/user/top_5_hogs.json"

    assert os.path.exists(output_path), f"Output file not found at {output_path}"

    try:
        with open(output_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File at {output_path} does not contain valid JSON")

    expected_data = [
        {"path": "/backup/db_dump.tar.gz", "size": 1500000000},
        {"path": "/home/user/videos/cat.mp4", "size": 800000000},
        {"path": "/home/user/docs.zip", "size": 600000000},
        {"path": "/var/data/db.sqlite", "size": 500000000},
        {"path": "/usr/lib/libhuge.so", "size": 420000000}
    ]

    assert isinstance(data, list), "Output JSON must be an array (list) of objects"
    assert len(data) == 5, f"Output JSON must contain exactly 5 items, found {len(data)}"

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object"
        assert "path" in actual, f"Item at index {i} is missing the 'path' key"
        assert "size" in actual, f"Item at index {i} is missing the 'size' key"

        assert actual["path"] == expected["path"], f"Expected path '{expected['path']}' at index {i}, but got '{actual['path']}'"
        assert actual["size"] == expected["size"], f"Expected size {expected['size']} at index {i}, but got {actual['size']}"

        # Ensure no extra keys are present
        assert set(actual.keys()) == {"path", "size"}, f"Item at index {i} has unexpected keys: {set(actual.keys()) - {'path', 'size'}}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
