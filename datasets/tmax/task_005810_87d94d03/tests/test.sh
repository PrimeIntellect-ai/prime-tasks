#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
from collections import defaultdict

def test_ci_results_correctness():
    exp_file = "/home/user/experiments.csv"
    idx_file = "/home/user/bootstrap_indices.txt"
    res_file = "/home/user/ci_results.txt"

    assert os.path.exists(res_file), f"File {res_file} does not exist."
    assert os.path.isfile(res_file), f"{res_file} is not a regular file."

    # 1. Parse experiments.csv to find the best lr
    lr_accs = defaultdict(list)
    with open(exp_file, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) > 1, "experiments.csv is empty or missing data."
    header = lines[0].split(",")
    lr_idx = header.index("lr")
    acc_idx = header.index("accuracy")

    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split(",")
        lr = parts[lr_idx]
        acc = float(parts[acc_idx])
        lr_accs[lr].append(acc)

    # Find best lr by average accuracy
    best_lr = max(lr_accs.keys(), key=lambda k: sum(lr_accs[k]) / len(lr_accs[k]))
    best_accs = lr_accs[best_lr]

    # 2. Read bootstrap_indices.txt and calculate means
    with open(idx_file, "r") as f:
        idx_lines = f.read().strip().split("\n")

    means = []
    for line in idx_lines:
        if not line.strip():
            continue
        indices = [int(x) for x in line.split(",")]
        sample = [best_accs[i-1] for i in indices]
        mean_val = sum(sample) / len(sample)
        # Format to exactly 4 decimal places as required
        means.append(float(f"{mean_val:.4f}"))

    # 3. Sort means and find 5th and 95th values
    means.sort()
    lower = means[4]  # 5th value (0-indexed)
    upper = means[94] # 95th value (0-indexed)

    expected_content = f"Lower: {lower:.4f}, Upper: {upper:.4f}"

    # 4. Validate output
    with open(res_file, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Incorrect content in {res_file}.\n"
        f"Expected: '{expected_content}'\n"
        f"Actual:   '{actual_content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
