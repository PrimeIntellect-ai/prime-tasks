#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def compute_expected_results():
    dataset_path = '/home/user/dataset.csv'
    if not os.path.exists(dataset_path):
        return None, None, None

    with open(dataset_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        data = []
        for row in reader:
            if row[0] == "NaN" or row[1] == "NaN":
                continue
            data.append((int(row[0]), int(row[1]), int(row[2])))

    n = len(data)
    if n == 0:
        return None, None, None

    # Pearson correlation
    sum_x = sum(d[0] for d in data)
    sum_y = sum(d[1] for d in data)
    sum_x2 = sum(d[0]**2 for d in data)
    sum_y2 = sum(d[1]**2 for d in data)
    sum_xy = sum(d[0]*d[1] for d in data)

    numerator = n * sum_xy - sum_x * sum_y
    denominator = math.sqrt((n * sum_x2 - sum_x**2) * (n * sum_y2 - sum_y**2))
    corr = numerator / denominator if denominator != 0 else 0
    expected_corr = f"{corr:.3f}"

    # 5-fold CV KNN
    fold_size = n // 5
    best_k = None
    best_acc = -1

    def dist(x1, y1, x2, y2):
        return math.sqrt((x1 - x2)**2 + (y1 - y2)**2)

    for k in [1, 3, 5, 7]:
        fold_accs = []
        for fold in range(5):
            start_idx = fold * fold_size
            end_idx = (fold + 1) * fold_size if fold < 4 else n

            test_set = data[start_idx:end_idx]

            correct = 0
            for test_row in test_set:
                dists = []
                for j, train_row in enumerate(data):
                    if start_idx <= j < end_idx:
                        continue # Skip test set rows
                    d = dist(test_row[0], test_row[1], train_row[0], train_row[1])
                    dists.append((d, j, train_row[2]))

                # Sort by distance, then by original index to break ties
                dists.sort(key=lambda x: (x[0], x[1]))
                neighbors = dists[:k]

                votes1 = sum(1 for neighbor in neighbors if neighbor[2] == 1)
                votes0 = sum(1 for neighbor in neighbors if neighbor[2] == 0)

                # Tie breaker: class 1
                pred = 1 if votes1 >= votes0 else 0
                if pred == test_row[2]:
                    correct += 1

            fold_accs.append(correct / len(test_set))

        mean_acc = sum(fold_accs) / 5.0
        # If there is a tie in cross-validation accuracy, choose the smaller K.
        # Since we iterate k in increasing order, we only update if strictly greater.
        if mean_acc > best_acc:
            best_acc = mean_acc
            best_k = k

    expected_acc = f"{best_acc:.3f}"
    return expected_corr, str(best_k), expected_acc

def test_pipeline_cpp_exists():
    assert os.path.exists("/home/user/pipeline.cpp"), "The file /home/user/pipeline.cpp does not exist."

def test_results_txt_exists():
    assert os.path.exists("/home/user/results.txt"), "The file /home/user/results.txt does not exist."

def test_results_content():
    expected_corr, expected_k, expected_acc = compute_expected_results()
    assert expected_corr is not None, "Failed to compute expected results because dataset is missing or empty."

    with open('/home/user/results.txt', 'r') as f:
        lines = [l.strip() for l in f.readlines()]

    assert len(lines) == 3, f"Expected exactly 3 lines in results.txt, found {len(lines)}."

    assert lines[0] == expected_corr, f"Line 1 (Pearson correlation) mismatch: expected {expected_corr}, got {lines[0]}."
    assert lines[1] == expected_k, f"Line 2 (Optimal K) mismatch: expected {expected_k}, got {lines[1]}."
    assert lines[2] == expected_acc, f"Line 3 (Cross-validation accuracy) mismatch: expected {expected_acc}, got {lines[2]}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
