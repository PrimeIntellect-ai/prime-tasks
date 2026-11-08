#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import unicodedata
import pytest

def levenshtein(s1, s2):
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]

def get_expected_records():
    raw_dir = '/home/user/data/raw_reviews'
    all_records = []

    # Read all raw JSON files
    for fname in os.listdir(raw_dir):
        if fname.endswith('.json'):
            with open(os.path.join(raw_dir, fname), 'r', encoding='utf-8') as f:
                all_records.extend(json.load(f))

    # Normalize review_text to NFC
    for rec in all_records:
        rec['review_text'] = unicodedata.normalize('NFC', rec['review_text'])

    # Group by user_id
    groups = {}
    for rec in all_records:
        groups.setdefault(rec['user_id'], []).append(rec)

    final_records = []

    for user_id, group_records in groups.items():
        clusters = []
        for rec in group_records:
            added_to_cluster = False
            for cluster in clusters:
                # Check distance against any item in the cluster (transitive assumption)
                for cluster_rec in cluster:
                    if levenshtein(rec['review_text'], cluster_rec['review_text']) <= 2:
                        cluster.append(rec)
                        added_to_cluster = True
                        break
                if added_to_cluster:
                    break
            if not added_to_cluster:
                clusters.append([rec])

        # Resolve each cluster
        for cluster in clusters:
            # Sort by timestamp (asc), then record_id (asc)
            cluster.sort(key=lambda x: (x['timestamp'], x['record_id']))
            final_records.append(cluster[0])

    # Sort final records by record_id
    final_records.sort(key=lambda x: x['record_id'])
    return final_records

def test_clean_reviews_csv():
    csv_path = '/home/user/data/clean_reviews.csv'
    assert os.path.isfile(csv_path), f"Output file {csv_path} does not exist."

    expected_records = get_expected_records()

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, "CSV file is empty."

    header = reader[0]
    expected_header = ['record_id', 'user_id', 'timestamp', 'review_text']
    assert header == expected_header, f"CSV header mismatch. Expected {expected_header}, got {header}"

    rows = reader[1:]
    assert len(rows) == len(expected_records), f"Expected {len(expected_records)} rows, got {len(rows)}."

    for i, (row, expected_rec) in enumerate(zip(rows, expected_records)):
        assert len(row) == 4, f"Row {i+1} does not have 4 columns."
        assert row[0] == expected_rec['record_id'], f"Row {i+1} record_id mismatch."
        assert row[1] == expected_rec['user_id'], f"Row {i+1} user_id mismatch."
        assert str(row[2]) == str(expected_rec['timestamp']), f"Row {i+1} timestamp mismatch."
        assert row[3] == expected_rec['review_text'], f"Row {i+1} review_text mismatch."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
