#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_path_analysis_json():
    json_file = '/home/user/path_analysis.json'

    assert os.path.exists(json_file), f"Expected output file {json_file} does not exist."
    assert os.path.isfile(json_file), f"{json_file} is not a file."

    with open(json_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_file} does not contain valid JSON.")

    assert "shortest_path" in data, "JSON output is missing the 'shortest_path' key."
    assert "centrality" in data, "JSON output is missing the 'centrality' key."

    expected_path_forward = ["E001", "E005", "E008", "E012"]
    expected_path_reverse = ["E012", "E008", "E005", "E001"]

    actual_path = data["shortest_path"]
    assert actual_path == expected_path_forward or actual_path == expected_path_reverse, \
        f"Expected shortest_path to be {expected_path_forward}, but got {actual_path}."

    expected_centrality = {
        "E001": 2,
        "E005": 4,
        "E008": 3,
        "E012": 1
    }

    actual_centrality = data["centrality"]
    assert actual_centrality == expected_centrality, \
        f"Expected centrality to be {expected_centrality}, but got {actual_centrality}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
