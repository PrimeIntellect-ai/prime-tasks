#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import math

def test_report_json_exists():
    path = '/home/user/report.json'
    assert os.path.exists(path), f"The file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

def test_report_json_content():
    path = '/home/user/report.json'
    assert os.path.exists(path), f"The file {path} is missing."

    with open(path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{path} is not valid JSON."

    # Read the data to compute truth dynamically
    csv_path = '/home/user/datasets_meta.csv'
    assert os.path.exists(csv_path), f"The file {csv_path} is missing."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        data = list(reader)

    # Step 1: Clean
    cleaned_data = []
    for row in data:
        num_rows = int(row['num_rows'])
        feature_std = float(row['feature_std'])
        if num_rows > 0 and feature_std > 0:
            cleaned_data.append(row)

    expected_cleaned_count = len(cleaned_data)

    # Step 2: Missing values
    valid_missing = []
    for row in cleaned_data:
        if row['missing_pct'] != '':
            valid_missing.append(float(row['missing_pct']))

    valid_missing.sort()
    n = len(valid_missing)
    if n % 2 == 0:
        median_missing = (valid_missing[n//2 - 1] + valid_missing[n//2]) / 2.0
    else:
        median_missing = valid_missing[n//2]

    for row in cleaned_data:
        if row['missing_pct'] == '':
            row['missing_pct'] = median_missing
        else:
            row['missing_pct'] = float(row['missing_pct'])

        row['num_rows'] = int(row['num_rows'])
        row['num_features'] = int(row['num_features'])
        row['feature_mean'] = float(row['feature_mean'])
        row['feature_std'] = float(row['feature_std'])

    # Step 3: Standardize and Distance
    cols = ['num_rows', 'num_features', 'missing_pct', 'feature_mean', 'feature_std']
    means = {}
    stds = {}

    for col in cols:
        vals = [r[col] for r in cleaned_data]
        mean_val = sum(vals) / len(vals)
        means[col] = mean_val
        variance = sum((x - mean_val) ** 2 for x in vals) / (len(vals) - 1)
        stds[col] = math.sqrt(variance)

    std_data = []
    target_vec = None
    for row in cleaned_data:
        std_row = {}
        for col in cols:
            std_row[col] = (row[col] - means[col]) / stds[col]
        if row['dataset_id'] == 'DS_Target':
            target_vec = std_row
        std_data.append((row['dataset_id'], std_row))

    distances = []
    for did, srow in std_data:
        if did == 'DS_Target':
            continue
        dist = math.sqrt(sum((srow[col] - target_vec[col]) ** 2 for col in cols))
        distances.append((did, dist))

    distances.sort(key=lambda x: x[1])
    expected_closest = [distances[0][0], distances[1][0]]

    # Step 4: Welch's t-test
    target_row = next(r for r in cleaned_data if r['dataset_id'] == 'DS_Target')
    closest_row = next(r for r in cleaned_data if r['dataset_id'] == expected_closest[0])

    m1, s1, n1 = target_row['feature_mean'], target_row['feature_std'], target_row['num_rows']
    m2, s2, n2 = closest_row['feature_mean'], closest_row['feature_std'], closest_row['num_rows']

    var1 = s1 ** 2
    var2 = s2 ** 2

    se = math.sqrt(var1 / n1 + var2 / n2)
    t_stat = (m1 - m2) / se

    # Degrees of freedom for Welch's t-test
    df_num = (var1 / n1 + var2 / n2) ** 2
    df_den = ((var1 / n1) ** 2) / (n1 - 1) + ((var2 / n2) ** 2) / (n2 - 1)
    df = df_num / df_den

    # We will compute p-value using scipy if available, or just use the expected value since it's standard
    try:
        from scipy.stats import t
        p_val = 2 * (1 - t.cdf(abs(t_stat), df))
    except ImportError:
        # Fallback to the known expected value if scipy is not available
        p_val = 0.2801

    expected_t_stat = round(t_stat, 2)
    expected_p_val = round(p_val, 4)
    expected_is_sig = expected_p_val < 0.05

    assert "cleaned_dataset_count" in report, "Missing 'cleaned_dataset_count' in report.json"
    assert report["cleaned_dataset_count"] == expected_cleaned_count, f"Expected cleaned_dataset_count {expected_cleaned_count}, got {report['cleaned_dataset_count']}"

    assert "closest_datasets" in report, "Missing 'closest_datasets' in report.json"
    assert report["closest_datasets"] == expected_closest, f"Expected closest_datasets {expected_closest}, got {report['closest_datasets']}"

    assert "t_stat" in report, "Missing 't_stat' in report.json"
    assert report["t_stat"] == expected_t_stat, f"Expected t_stat {expected_t_stat}, got {report['t_stat']}"

    assert "p_value" in report, "Missing 'p_value' in report.json"
    assert abs(report["p_value"] - expected_p_val) <= 0.0001, f"Expected p_value {expected_p_val}, got {report['p_value']}"

    assert "is_significantly_different" in report, "Missing 'is_significantly_different' in report.json"
    assert report["is_significantly_different"] == expected_is_sig, f"Expected is_significantly_different {expected_is_sig}, got {report['is_significantly_different']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
