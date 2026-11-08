#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json

def test_summary_json_exists():
    """Test that the summary.json file was generated."""
    file_path = "/home/user/summary.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing. The Rust program did not generate the output."

def test_summary_json_content():
    """Test that the summary.json file contains the exact expected processed records."""
    file_path = "/home/user/summary.json"

    with open(file_path, 'r', encoding='utf-8') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {file_path} does not contain valid JSON."

    expected_data = [
      {
        "user_id": "U101",
        "error_code": "E9999",
        "hash": "baf67c1e33c2a6311ce808da76c2415d861d85fb70bf81be5f278d6556e804f5"
      },
      {
        "user_id": "U102",
        "error_code": "E1042",
        "hash": "21396eb516c965e636f3db1ec5dd305ee4c9ce137e937d12f36f6dcc4655f46a"
      },
      {
        "user_id": "U102",
        "error_code": "E2099",
        "hash": "d13be6ceceaf8c433c242e20bba808e016a24eb870024443af1d2795ceb8b0e7"
      },
      {
        "user_id": "U105",
        "error_code": "E5001",
        "hash": "95a51a9463e273010b9777ca22be990f1352e8006e88fb986e3fdfb0d772ecf6"
      }
    ]

    assert isinstance(actual_data, list), f"Expected JSON root to be a list, but got {type(actual_data).__name__}."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, but got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, (
            f"Record at index {i} does not match expected.\n"
            f"Expected: {expected}\n"
            f"Actual: {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
