#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_rotation_result_file():
    """Verify that the rotation_result.json file exists and contains the correct response."""
    result_path = '/home/user/rotation_result.json'

    assert os.path.isfile(result_path), f"The file {result_path} does not exist. Did you save the server response?"

    with open(result_path, 'r') as f:
        content = f.read()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"The file {result_path} does not contain valid JSON. Content: {content}")

    expected_data = {"status": "success", "new_credential": "FLAG_ROTATED_99321"}
    assert data == expected_data, f"The JSON content in {result_path} does not match the expected server response. Found: {data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
