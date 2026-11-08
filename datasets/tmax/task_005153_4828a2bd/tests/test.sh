#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import pytest

def test_extracted_metadata_f1_score():
    """
    Validates that the extracted metadata JSON file exists and its contents
    achieve an F1 score of at least 0.95 compared to the hidden ground truth.
    """
    user_file = "/home/user/extracted_metadata.json"
    truth_file = "/tests/ground_truth.json"

    assert os.path.exists(user_file), f"Output file {user_file} does not exist. Please ensure your script generates the correct output file."
    assert os.path.exists(truth_file), f"Ground truth file {truth_file} does not exist. The test environment might be corrupted."

    try:
        with open(user_file, "r") as f:
            user_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Output file {user_file} is not a valid JSON.")

    with open(truth_file, "r") as f:
        truth_data = json.load(f)

    true_positives = 0
    false_positives = 0
    false_negatives = 0

    for k, v in user_data.items():
        if k in truth_data:
            try:
                # Compare as floats to handle int/float/bool representations gracefully
                if abs(float(v) - float(truth_data[k])) < 0.01:
                    true_positives += 1
                else:
                    false_posititives += 1
            except (ValueError, TypeError):
                # If conversion to float fails, consider it a false positive
                false_positives += 1
        else:
            false_positives += 1

    for k in truth_data:
        if k not in user_data:
            false_negatives += 1

    precision = true_positives / (true_positives + false_positives) if (true_positives + false_positives) > 0 else 0
    recall = true_positives / (true_positives + false_negatives) if (true_positives + false_negatives) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0

    assert f1 >= 0.95, (
        f"F1 Score {f1:.4f} is below the required threshold of 0.95. "
        f"Metrics - True Positives: {true_positives}, False Positives: {false_positives}, "
        f"False Negatives: {false_negatives}. Precision: {precision:.4f}, Recall: {recall:.4f}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
