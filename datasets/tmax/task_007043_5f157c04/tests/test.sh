#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_metrics_json_exists():
    assert os.path.isfile('/home/user/metrics.json'), "The file /home/user/metrics.json does not exist."

def test_metrics_json_content():
    with open('/home/user/metrics.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/metrics.json is not a valid JSON file.")

    expected_keys = {
        "seq_len_ci_low",
        "seq_len_ci_high",
        "bfactor_norm_loc",
        "bfactor_norm_scale"
    }

    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in metrics.json: {missing_keys}"

    # Assert values
    assert isinstance(data["seq_len_ci_low"], (int, float)), "seq_len_ci_low must be a float"
    assert isinstance(data["seq_len_ci_high"], (int, float)), "seq_len_ci_high must be a float"
    assert isinstance(data["bfactor_norm_loc"], (int, float)), "bfactor_norm_loc must be a float"
    assert isinstance(data["bfactor_norm_scale"], (int, float)), "bfactor_norm_scale must be a float"

    assert round(data["seq_len_ci_low"], 4) == 10.6000, f"Expected seq_len_ci_low to be 10.6, got {data['seq_len_ci_low']}"
    assert round(data["seq_len_ci_high"], 4) == 25.8000, f"Expected seq_len_ci_high to be 25.8, got {data['seq_len_ci_high']}"
    assert round(data["bfactor_norm_loc"], 4) == 20.3333, f"Expected bfactor_norm_loc to be 20.3333, got {data['bfactor_norm_loc']}"
    assert round(data["bfactor_norm_scale"], 4) == 6.5746, f"Expected bfactor_norm_scale to be 6.5746, got {data['bfactor_norm_scale']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
