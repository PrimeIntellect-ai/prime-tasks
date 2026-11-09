#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import pytest

def test_f1_score_of_matches():
    pred_path = '/app/matches.json'
    assert os.path.isfile(pred_path), f"Output file {pred_path} does not exist."

    try:
        with open(pred_path, 'r') as f:
            preds = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to read or parse {pred_path} as JSON: {e}")

    # The expected truth derived from the database setup
    truth = [
        {"user_id": 1, "product_id": 2, "category_id": 3}
    ]

    try:
        pred_set = set(tuple(sorted(d.items())) for d in preds)
    except Exception as e:
        pytest.fail(f"Failed to process predictions. Ensure output is a list of dictionaries. Error: {e}")

    truth_set = set(tuple(sorted(d.items())) for d in truth)

    tp = len(pred_set & truth_set)
    fp = len(pred_set - truth_set)
    fn = len(truth_set - pred_set)

    if tp == 0:
        f1 = 0.0
    else:
        precision = tp / (tp + fp)
        recall = tp / (tp + fn)
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.95, f"F1 Score {f1:.4f} is below the threshold of 0.95. TP:{tp}, FP:{fp}, FN:{fn}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
