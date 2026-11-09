#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math

import pandas as pd
from scipy.stats import ttest_ind
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler


def get_csv_data(filepath):
    with open(filepath, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        data = [[] for _ in header]
        for row in reader:
            for i, val in enumerate(row):
                data[i].append(float(val))
    return header, data


def mean(lst):
    return sum(lst) / len(lst)


def std(lst, m):
    return math.sqrt(sum((x - m) ** 2 for x in lst))


def calc_corr(xs, ys):
    mx = mean(xs)
    my = mean(ys)
    sx = std(xs, mx)
    sy = std(ys, my)
    if sx == 0 or sy == 0:
        return 0
    cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    return cov / (sx * sy)


def test_results_json_exists():
    assert os.path.exists('/home/user/results.json'), '/home/user/results.json does not exist.'
    assert os.path.isfile('/home/user/results.json'), '/home/user/results.json is not a file.'


def test_results_json_structure_and_values():
    with open('/home/user/results.json', 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, '/home/user/results.json is not a valid JSON file.'

    assert 'dropped_features' in results, "Key 'dropped_features' missing from JSON."
    assert 'significant_components' in results, "Key 'significant_components' missing from JSON."
    assert 'model_accuracy' in results, "Key 'model_accuracy' missing from JSON."

    # Preserve the original independent correlation check.
    header, data = get_csv_data('/home/user/chemical_data.csv')
    if 'is_toxic' in header:
        target_idx = header.index('is_toxic')
        features = header[:target_idx] + header[target_idx + 1:]
        feature_data = data[:target_idx] + data[target_idx + 1:]
    else:
        features = header
        feature_data = data

    kept_cols = []
    dropped_cols = []
    kept_data = []
    for i, col in enumerate(features):
        col_data = feature_data[i]
        if not kept_cols:
            kept_cols.append(col)
            kept_data.append(col_data)
        else:
            max_corr = 0
            for k_data in kept_data:
                c = abs(calc_corr(col_data, k_data))
                if c > max_corr:
                    max_corr = c
            if max_corr > 0.85:
                dropped_cols.append(col)
            else:
                kept_cols.append(col)
                kept_data.append(col_data)

    assert isinstance(results['dropped_features'], list), "'dropped_features' must be a list."
    assert results['dropped_features'] == dropped_cols, (
        f"Expected dropped_features to be {dropped_cols}, got {results['dropped_features']}."
    )

    sig_comps = results['significant_components']
    assert isinstance(sig_comps, list), "'significant_components' must be a list."
    assert all(isinstance(x, int) for x in sig_comps), "'significant_components' must contain only integers."
    assert all(0 <= x <= 4 for x in sig_comps), "'significant_components' values must be between 0 and 4."
    assert sig_comps == sorted(sig_comps), "'significant_components' must be sorted in ascending order."
    assert len(sig_comps) == len(set(sig_comps)), "'significant_components' must not contain duplicates."

    acc = results['model_accuracy']
    assert isinstance(acc, float), "'model_accuracy' must be a float."
    assert 0.0 <= acc <= 1.0, "'model_accuracy' must be between 0.0 and 1.0."
    acc_str = str(acc)
    if '.' in acc_str:
        decimals = len(acc_str.split('.')[1])
        assert decimals <= 4, "'model_accuracy' should be rounded to exactly 4 decimal places."

    # Recompute the PCA, Welch tests, and logistic-regression training accuracy.
    df = pd.read_csv('/home/user/chemical_data.csv')
    y = df['is_toxic']
    standardized = StandardScaler().fit_transform(df[kept_cols])
    components = PCA(n_components=5).fit_transform(standardized)

    expected_sig_comps = []
    for component_idx in range(5):
        toxic_values = components[y.to_numpy() == 1, component_idx]
        non_toxic_values = components[y.to_numpy() == 0, component_idx]
        p_value = ttest_ind(toxic_values, non_toxic_values, equal_var=False).pvalue
        if p_value < 0.05:
            expected_sig_comps.append(component_idx)

    assert sig_comps == expected_sig_comps, (
        f"Expected significant_components to be {expected_sig_comps}, got {sig_comps}."
    )
    assert expected_sig_comps, 'The dataset produced no significant components, so classification cannot be verified.'

    model = LogisticRegression(random_state=42)
    model.fit(components[:, expected_sig_comps], y)
    expected_accuracy = round(float(model.score(components[:, expected_sig_comps], y)), 4)
    assert acc == expected_accuracy, (
        f"Expected model_accuracy to be {expected_accuracy}, got {acc}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
