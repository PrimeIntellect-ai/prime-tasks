#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_verified_paths_json_exists_and_correct():
    path = '/home/user/verified_paths.json'
    assert os.path.isfile(path), f"File {path} does not exist. Did you export the results?"

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not a valid JSON file.")

    expected = [
        {"employee_id": "E003", "hops": 2, "path": ["E003", "E002", "E001"]},
        {"employee_id": "E004", "hops": 3, "path": ["E004", "E003", "E002", "E001"]},
        {"employee_id": "E005", "hops": 3, "path": ["E005", "E003", "E002", "E001"]},
        {"employee_id": "E007", "hops": 2, "path": ["E007", "E006", "E001"]}
    ]

    assert isinstance(data, list), "The JSON output must be a list of objects."
    assert len(data) == len(expected), f"Expected {len(expected)} records, but found {len(data)}."

    # Check each record
    for i, (actual_record, expected_record) in enumerate(zip(data, expected)):
        assert actual_record == expected_record, f"Record at index {i} does not match expected output. Expected: {expected_record}, Actual: {actual_record}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
