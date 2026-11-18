#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_cov_sum_exists_and_correct():
    """
    Validates that cov_sum.txt exists, and contains the correct sum of the 
    covariance matrix computed without precision loss on the timestamp.
    """
    output_path = '/home/user/cov_sum.txt'
    data_path = '/home/user/sensor_data.csv'

    assert os.path.exists(output_path), f"Output file missing: {output_path}"
    assert os.path.exists(data_path), f"Data file missing: {data_path}"

    # Recompute the expected covariance sum using standard library to ensure precision
    groups = {}
    with open(data_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            ts, a, b, c = row
            if ts == 'MISSING':
                continue

            # Keep as integer to prevent precision loss
            ts_int = int(ts)
            if ts_int not in groups:
                groups[ts_int] = [[], [], []]

            if a != 'MISSING': groups[ts_int][0].append(float(a))
            if b != 'MISSING': groups[ts_int][1].append(float(b))
            if c != 'MISSING': groups[ts_int][2].append(float(c))

    # Compute means per group (simulating pandas groupby.mean())
    group_means = []
    for ts in sorted(groups.keys()):
        g = groups[ts]
        mean_a = sum(g[0]) / len(g[0]) if g[0] else None
        mean_b = sum(g[1]) / len(g[1]) if g[1] else None
        mean_c = sum(g[2]) / len(g[2]) if g[2] else None
        group_means.append((mean_a, mean_b, mean_c))

    # Compute pairwise covariance (simulating pandas .cov())
    expected_cov_sum = 0.0
    for i in range(3):
        for j in range(3):
            # Pandas computes covariance for each pair using rows where both are valid
            pairs = [(m[i], m[j]) for m in group_means if m[i] is not None and m[j] is not None]
            n_pair = len(pairs)
            if n_pair < 2:
                continue

            mean_i = sum(p[0] for p in pairs) / n_pair
            mean_j = sum(p[1] for p in pairs) / n_pair

            # Sample covariance (ddof=1)
            s = sum((p[0] - mean_i) * (p[1] - mean_j) for p in pairs)
            expected_cov_sum += s / (n_pair - 1)

    expected_str = f"{expected_cov_sum:.4f}"

    with open(output_path, 'r') as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, (
        f"Incorrect covariance sum in {output_path}.\n"
        f"Expected: {expected_str}\n"
        f"Actual: {actual_str}\n"
        f"This indicates precision was likely lost during timestamp conversion."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
