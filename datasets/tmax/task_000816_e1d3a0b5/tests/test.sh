#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def load_csv_data(path):
    try:
        with open(path, 'r', newline='', encoding='utf-8') as f:
            reader = csv.reader(f)
            headers = next(reader)
            return headers, [tuple(row) for row in reader]
    except Exception:
        return [], []

def test_processed_logs_f1_score():
    submission_path = '/home/user/processed_logs.csv'
    reference_path = '/tests/reference_logs.csv'

    assert os.path.isfile(submission_path), f"Output file missing: {submission_path}"
    assert os.path.isfile(reference_path), f"Reference file missing: {reference_path}"

    sub_headers, sub_data = load_csv_data(submission_path)
    ref_headers, ref_data = load_csv_data(reference_path)

    assert sub_headers == ['SessionID', 'Timestamp', 'EventID', 'GateStatus'], \
        f"Output CSV headers are incorrect. Expected ['SessionID', 'Timestamp', 'EventID', 'GateStatus'], got {sub_headers}"

    reference_set = set(ref_data)
    submission_set = set(sub_data)

    assert len(reference_set) > 0, "Reference dataset is empty."

    true_positives = len(reference_set.intersection(submission_set))
    false_positives = len(submission_set - reference_set)
    false_negatives = len(reference_set - submission_set)

    precision = true_positives / (true_positives + false_positives) if (true_positives + false_positives) > 0 else 0
    recall = true_positives / (true_positives + false_negatives) if (true_posititives + false_negatives) > 0 else 0

    if precision + recall == 0:
        f1 = 0.0
    else:
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.95, f"F1 Score is too low: {f1:.4f} (Threshold: 0.95). TP:{true_positives}, FP:{false_positives}, FN:{false_negatives}"

def test_processed_logs_sorting():
    submission_path = '/home/user/processed_logs.csv'
    _, sub_data = load_csv_data(submission_path)

    if len(sub_data) > 0:
        sorted_data = sorted(sub_data, key=lambda x: (x[0], x[1]))
        assert sub_data == sorted_data, "The output CSV is not correctly sorted by SessionID and Timestamp."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
