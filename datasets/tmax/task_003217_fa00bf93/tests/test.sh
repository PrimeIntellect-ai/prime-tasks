#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_reconstructed_edges_f1_score():
    output_path = "/home/user/reconstructed_edges.csv"
    assert os.path.isfile(output_path), f"Output file not found: {output_path}"

    truth = {
        ("WEB_FRONTEND", "STORAGE_NAS1"),
        ("STORAGE_NAS1", "CLOUD_BUCKET_B"),
        ("DB_MAIN", "STORAGE_SAN1"),
        ("REDIS_CACHE", "STORAGE_NAS2"),
        ("STORAGE_SAN1", "CLOUD_BUCKET_A")
    }

    predicted = set()
    with open(output_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None, "CSV must have a header"
        assert "source" in reader.fieldnames, "CSV header must contain 'source'"
        assert "target" in reader.fieldnames, "CSV header must contain 'target'"

        for row in reader:
            predicted.add((row["source"].strip(), row["target"].strip()))

    true_positives = len(truth.intersection(predicted))
    false_positives = len(predicted - truth)
    false_negatives = len(truth - predicted)

    if true_positives == 0:
        f1 = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)
        recall = true_positives / (true_positives + false_negatives)
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.90, f"F1 Score {f1:.3f} is below the threshold of 0.90. Missing edges: {truth - predicted}. Extra edges: {predicted - truth}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
