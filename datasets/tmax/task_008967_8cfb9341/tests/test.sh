#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_recommendations_file_exists():
    assert os.path.isfile("/home/user/recommendations.json"), "/home/user/recommendations.json is missing. Did you generate the output file?"

def test_recommendations_content():
    assert os.path.isfile("/home/user/recommendations.json"), "/home/user/recommendations.json does not exist."
    assert os.path.isfile("/tests/ground_truth.json"), "Ground truth file is missing from the verifier tests."

    with open("/home/user/recommendations.json", "r") as f:
        try:
            student_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/recommendations.json is not a valid JSON file.")

    with open("/tests/ground_truth.json", "r") as f:
        ground_truth = json.load(f)

    assert "user_42" in student_output, "The key 'user_42' is missing from the output JSON."

    student_tracks = student_output["user_42"]
    truth_tracks = ground_truth["user_42"]

    assert isinstance(student_tracks, list), "The value for 'user_42' should be a list of track IDs."
    assert len(student_tracks) == 3, f"Expected exactly 3 track IDs, but got {len(student_tracks)}."

    assert student_tracks == truth_tracks, f"The recommended tracks do not match the expected tracks. Expected {truth_tracks}, got {student_tracks}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
