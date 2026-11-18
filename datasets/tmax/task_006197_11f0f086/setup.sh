#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import csv
import random

random.seed(42)
with open("/home/user/dataset.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["Feature_A", "Feature_B", "Label"])
    for i in range(120):
        # Introduce NaNs
        if i % 7 == 0:
            writer.writerow(["NaN", int(random.gauss(50, 10)), random.choice([0, 1])])
            continue
        if i % 13 == 0:
            writer.writerow([int(random.gauss(50, 10)), "NaN", random.choice([0, 1])])
            continue

        feat_a = int(random.uniform(10, 100))
        feat_b = feat_a * 2 + int(random.gauss(0, 15))

        # Label logic
        label = 1 if (feat_a + feat_b) > 160 else 0

        writer.writerow([feat_a, feat_b, label])
EOF

    python3 /home/user/generate_data.py

    cat << 'EOF' > /home/user/verify.py
import sys
import pandas as pd
import numpy as np
from sklearn.metrics import accuracy_score
import math

df = pd.read_csv('/home/user/dataset.csv')
# Keep only valid rows
df = df[~df['Feature_A'].astype(str).str.contains("NaN") & ~df['Feature_B'].astype(str).str.contains("NaN")].copy()
df['Feature_A'] = df['Feature_A'].astype(int)
df['Feature_B'] = df['Feature_B'].astype(int)
df['Label'] = df['Label'].astype(int)

# 1. Pearson correlation
corr = df['Feature_A'].corr(df['Feature_B'])
expected_corr = f"{corr:.3f}"

# 2. 5-fold CV KNN
N = len(df)
fold_size = N // 5

def euclidean_dist(x1, y1, x2, y2):
    return math.sqrt((x1 - x2)**2 + (y1 - y2)**2)

best_k = None
best_acc = -1

for k in [1, 3, 5, 7]:
    fold_accs = []
    for fold in range(5):
        start_idx = fold * fold_size
        end_idx = (fold + 1) * fold_size if fold < 4 else N

        test_df = df.iloc[start_idx:end_idx]
        train_df = pd.concat([df.iloc[:start_idx], df.iloc[end_idx:]])

        correct = 0
        for _, test_row in test_df.iterrows():
            dists = []
            for train_idx, train_row in train_df.iterrows():
                d = euclidean_dist(test_row['Feature_A'], test_row['Feature_B'], train_row['Feature_A'], train_row['Feature_B'])
                dists.append((d, train_idx, train_row['Label']))

            # Sort by distance, then original index to match c++ logic
            dists.sort(key=lambda x: (x[0], x[1]))
            neighbors = dists[:k]
            votes = {0: 0, 1: 0}
            for n in neighbors:
                votes[n[2]] += 1

            # Tie breaker: class 1
            if votes[1] >= votes[0]:
                pred = 1
            else:
                pred = 0

            if pred == test_row['Label']:
                correct += 1

        fold_accs.append(correct / len(test_df))

    mean_acc = sum(fold_accs) / 5.0
    if mean_acc > best_acc:
        best_acc = mean_acc
        best_k = k

expected_acc = f"{best_acc:.3f}"

# Check results
with open('/home/user/results.txt', 'r') as f:
    lines = [l.strip() for l in f.readlines()]

if lines[0] != expected_corr:
    print(f"Error: expected corr {expected_corr}, got {lines[0]}")
    sys.exit(1)
if int(lines[1]) != best_k:
    print(f"Error: expected k {best_k}, got {lines[1]}")
    sys.exit(1)
if lines[2] != expected_acc:
    print(f"Error: expected acc {expected_acc}, got {lines[2]}")
    sys.exit(1)

print("Pass")
sys.exit(0)
EOF

    chmod -R 777 /home/user
