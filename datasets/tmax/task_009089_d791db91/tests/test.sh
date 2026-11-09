#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
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

@pytest.fixture(scope="module")
def expected_data():
    input_csv = '/home/user/config_changes.csv'
    assert os.path.exists(input_csv), f"Input file {input_csv} is missing."

    category_distances = {}
    top_changes = {}

    with open(input_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            cat = row['Category']
            dist = levenshtein(row['OldValue'], row['NewValue'])

            if cat not in category_distances:
                category_distances[cat] = []
            category_distances[cat].append(dist)

            if cat not in top_changes:
                top_changes[cat] = (dist, row)
            else:
                if dist > top_changes[cat][0]:
                    top_changes[cat] = (dist, row)

    expected_stats = []
    for cat in sorted(category_distances.keys()):
        dists = category_distances[cat]
        avg = sum(dists) / len(dists)
        expected_stats.append(f"{cat},{avg:.2f}")

    expected_top = []
    for cat in sorted(top_changes.keys()):
        dist, row = top_changes[cat]
        expected_top.append(f"{cat},{row['Timestamp']},{row['ServerID']},{row['ConfigKey']},{dist}")

    return expected_stats, expected_top

def test_category_stats_csv(expected_data):
    expected_stats, _ = expected_data
    stats_file = '/home/user/category_stats.csv'
    assert os.path.exists(stats_file), f"Output file {stats_file} is missing."

    with open(stats_file, 'r', encoding='utf-8') as f:
        actual_stats = [line.strip() for line in f if line.strip()]

    assert actual_stats == expected_stats, f"Contents of {stats_file} do not match expected.\nExpected: {expected_stats}\nActual: {actual_stats}"

def test_top_changes_csv(expected_data):
    _, expected_top = expected_data
    top_file = '/home/user/top_changes.csv'
    assert os.path.exists(top_file), f"Output file {top_file} is missing."

    with open(top_file, 'r', encoding='utf-8') as f:
        actual_top = [line.strip() for line in f if line.strip()]

    assert actual_top == expected_top, f"Contents of {top_file} do not match expected.\nExpected: {expected_top}\nActual: {actual_top}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
