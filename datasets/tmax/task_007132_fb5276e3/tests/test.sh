#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import hashlib
import pytest

def compute_bigrams(text):
    return set(text[i:i+2] for i in range(len(text) - 1))

def jaccard_similarity(set1, set2):
    if not set1 and not set2:
        return 1.0
    intersection = len(set1.intersection(set2))
    union = len(set1.union(set2))
    return intersection / union if union > 0 else 0.0

def test_metrics_csv_exists():
    output_file = "/home/user/output/metrics.csv"
    assert os.path.exists(output_file), f"Output file does not exist: {output_file}"
    assert os.path.isfile(output_file), f"Output path is not a file: {output_file}"

def test_metrics_csv_content():
    input_file = "/home/user/input/retries.tsv"
    output_file = "/home/user/output/metrics.csv"

    assert os.path.exists(input_file), f"Input file missing: {input_file}"

    # Read and deduplicate
    seen_texts = set()
    deduped_texts = []

    with open(input_file, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                text = parts[1]
                if text not in seen_texts:
                    seen_texts.add(text)
                    deduped_texts.append(text)

    # Compute expected results
    expected_results = []
    bigrams_list = [compute_bigrams(t) for t in deduped_texts]

    for i, text in enumerate(deduped_texts):
        text_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()

        if i == 0:
            rolling_sim = 0.0
        elif i == 1:
            rolling_sim = jaccard_similarity(bigrams_list[i], bigrams_list[i-1])
        else:
            sim1 = jaccard_similarity(bigrams_list[i], bigrams_list[i-1])
            sim2 = jaccard_similarity(bigrams_list[i], bigrams_list[i-2])
            rolling_sim = (sim1 + sim2) / 2.0

        expected_results.append((text_hash, f"{rolling_sim:.4f}"))

    # Read actual results
    actual_results = []
    with open(output_file, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["hash", "rolling_similarity"], f"Incorrect header in CSV: {header}"
        for row in reader:
            if row:
                actual_results.append(tuple(row))

    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} rows, got {len(actual_results)}"

    for i, (expected, actual) in enumerate(zip(expected_results, actual_results)):
        assert expected == actual, f"Row {i+1} mismatch. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
