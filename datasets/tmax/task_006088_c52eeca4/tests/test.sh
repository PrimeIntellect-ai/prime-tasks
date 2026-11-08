#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_most_similar_json_exists():
    """Check if the most_similar.json file was created."""
    assert os.path.isfile("/home/user/most_similar.json"), "The file /home/user/most_similar.json is missing."

def test_most_similar_json_content():
    """Check if the most_similar.json file contains the correct result."""
    filepath = "/home/user/most_similar.json"
    assert os.path.isfile(filepath), "The file /home/user/most_similar.json is missing."

    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/most_similar.json does not contain valid JSON.")

    assert "exp1" in data, "Key 'exp1' is missing from the JSON output."
    assert "exp2" in data, "Key 'exp2' is missing from the JSON output."
    assert "similarity" in data, "Key 'similarity' is missing from the JSON output."

    assert data["exp1"] == "exp_alpha", f"Expected 'exp1' to be 'exp_alpha', but got '{data['exp1']}'."
    assert data["exp2"] == "exp_beta", f"Expected 'exp2' to be 'exp_beta', but got '{data['exp2']}'."

    similarity = data["similarity"]
    assert isinstance(similarity, (int, float)), "Similarity score must be a number."
    assert round(similarity, 4) == 0.9990, f"Expected similarity to be 0.9990, but got {similarity}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
