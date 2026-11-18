#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import json
import math
import numpy as np

def read_csv(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        return list(reader), reader.fieldnames

def test_processed_data():
    raw_path = '/home/user/raw_data.csv'
    weights_path = '/home/user/model_weights.json'
    processed_path = '/home/user/processed_data.csv'

    assert os.path.exists(processed_path), f"{processed_path} does not exist."

    raw_data, _ = read_csv(raw_path)
    with open(weights_path, 'r', encoding='utf-8') as f:
        weights = json.load(f)

    # Compute target means for category_c
    cat_sums = {}
    cat_counts = {}
    for row in raw_data:
        cat = row['category_c']
        tgt = int(row['target'])
        cat_sums[cat] = cat_sums.get(cat, 0) + tgt
        cat_counts[cat] = cat_counts.get(cat, 0) + 1

    cat_means = {cat: cat_sums[cat] / cat_counts[cat] for cat in cat_sums}

    expected_processed = []
    for row in raw_data:
        var_a = float(row['var_a'])
        var_b = float(row['var_b'])
        f1 = var_a * var_b
        f2 = var_a**2 + var_b**2
        cat_enc = cat_means[row['category_c']]

        z = (weights['intercept'] +
             weights['w_f1'] * f1 +
             weights['w_f2'] * f2 +
             weights['w_cat'] * cat_enc)
        prob = 1 / (1 + math.exp(-z))

        expected_processed.append({
            'id': int(row['id']),
            'feature_1': round(f1, 4),
            'feature_2': round(f2, 4),
            'category_c_encoded': round(cat_enc, 4),
            'baseline_prob': round(prob, 4),
            'target': int(row['target'])
        })

    expected_processed.sort(key=lambda x: x['id'])

    actual_processed, actual_cols = read_csv(processed_path)
    expected_cols = ['id', 'feature_1', 'feature_2', 'category_c_encoded', 'baseline_prob', 'target']

    assert actual_cols == expected_cols, f"Expected columns {expected_cols}, got {actual_cols}"
    assert len(actual_processed) == len(expected_processed), f"Expected {len(expected_processed)} rows, got {len(actual_processed)}"

    for i, (actual, expected) in enumerate(zip(actual_processed, expected_processed)):
        assert int(actual['id']) == expected['id'], f"Row {i}: Expected id {expected['id']}, got {actual['id']}"
        assert float(actual['feature_1']) == expected['feature_1'], f"Row {i}: Expected feature_1 {expected['feature_1']}, got {actual['feature_1']}"
        assert float(actual['feature_2']) == expected['feature_2'], f"Row {i}: Expected feature_2 {expected['feature_2']}, got {actual['feature_2']}"
        assert float(actual['category_c_encoded']) == expected['category_c_encoded'], f"Row {i}: Expected category_c_encoded {expected['category_c_encoded']}, got {actual['category_c_encoded']}"
        assert float(actual['baseline_prob']) == expected['baseline_prob'], f"Row {i}: Expected baseline_prob {expected['baseline_prob']}, got {actual['baseline_prob']}"
        assert int(actual['target']) == expected['target'], f"Row {i}: Expected target {expected['target']}, got {actual['target']}"

def test_bootstrap_means():
    bootstrap_path = '/home/user/bootstrap_means.csv'
    processed_path = '/home/user/processed_data.csv'

    assert os.path.exists(bootstrap_path), f"{bootstrap_path} does not exist."

    actual_means, actual_cols = read_csv(bootstrap_path)
    assert actual_cols == ['mean_prob'], f"Expected column ['mean_prob'], got {actual_cols}"
    assert len(actual_means) == 100, f"Expected 100 bootstrap means, got {len(actual_means)}"

    means = [float(row['mean_prob']) for row in actual_means]

    # Check if sorted
    assert means == sorted(means), "The bootstrap means are not sorted in ascending order."

    # Check statistical properties against processed data
    processed_data, _ = read_csv(processed_path)
    orig_probs = [float(row['baseline_prob']) for row in processed_data]
    orig_mean = sum(orig_probs) / len(orig_probs)

    mean_of_means = sum(means) / len(means)

    # The mean of the bootstrap means should be very close to the original sample mean
    assert abs(mean_of_means - orig_mean) < 0.05, f"Bootstrap mean of means ({mean_of_means}) is too far from original mean ({orig_mean})."

    # Reproduce the required seeded bootstrap exactly and verify every result.
    probs = np.asarray(orig_probs, dtype=float)
    n = len(probs)
    np.random.seed(42)
    expected_means = []
    for _ in range(100):
        indices = np.random.choice(n, size=n, replace=True)
        expected_means.append(round(float(np.mean(probs[indices])), 4))
    expected_means.sort()

    assert means == expected_means, (
        f"Bootstrap means do not match the 100 samples generated with numpy seed 42. "
        f"Expected {expected_means}, got {means}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
