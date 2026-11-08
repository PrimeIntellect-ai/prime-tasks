#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_process_drifts_script_exists():
    """Test that the agent created the process_drifts.py script."""
    script_path = "/home/user/process_drifts.py"
    assert os.path.isfile(script_path), f"The script {script_path} was not created."

def test_drift_summary_json_exists():
    """Test that the output JSON file exists."""
    output_path = "/home/user/drift_summary.json"
    assert os.path.isfile(output_path), f"The output file {output_path} was not created."

def test_drift_summary_matches_golden():
    """Test that the generated drift summary matches the expected golden data exactly."""
    output_path = "/home/user/drift_summary.json"
    golden_path = "/tests/.golden_summary.json"

    assert os.path.isfile(output_path), f"Missing {output_path}"
    assert os.path.isfile(golden_path), f"Missing {golden_path}"

    with open(output_path, 'r') as f_out:
        try:
            agent_data = json.load(f_out)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} is not valid JSON.")

    with open(golden_path, 'r') as f_gold:
        golden_data = json.load(f_gold)

    assert agent_data == golden_data, "The contents of drift_summary.json do not match the expected output. Check grouping, chronological sorting, and extraction logic."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
