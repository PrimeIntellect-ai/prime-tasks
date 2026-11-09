#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def load_csv(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return set(line.strip() for line in f if line.strip() and not line.lower().startswith('timestamp'))
    except Exception:
        return set()


def test_anomalies_f1_score():
    predicted_path = '/home/user/anomalies.csv'
    expected_path = '/tests/expected_anomalies.csv'

    assert os.path.isfile(predicted_path), f"Output file {predicted_path} does not exist."
    assert os.path.isfile(expected_path), f"Expected anomalies file {expected_path} is missing."

    predicted = load_csv(predicted_path)
    expected = load_csv(expected_path)

    assert expected, "Expected anomalies set is empty, cannot compute F1 score."

    true_positives = len(predicted.intersection(expected))
    false_positives = len(predicted - expected)
    false_negatives = len(expected - predicted)

    if true_positives == 0:
        f1 = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)
        recall = true_positives / (true_positives + false_negatives)
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.95, f"F1 score {f1:.4f} is below the threshold of 0.95. TP: {true_positives}, FP: {false_positives}, FN: {false_negatives}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
