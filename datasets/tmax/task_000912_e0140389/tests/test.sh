#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import math

def read_csv(filepath):
    with open(filepath, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        data = []
        for row in reader:
            parsed_row = []
            for val in row:
                if val == '' or val.lower() == 'nan':
                    parsed_row.append(None)
                else:
                    parsed_row.append(float(val))
            data.append(parsed_row)
    return header, data

def ffill_bfill(data):
    n_rows = len(data)
    n_cols = len(data[0])

    # ffill
    for j in range(n_cols):
        last_valid = None
        for i in range(n_rows):
            if data[i][j] is not None:
                last_valid = data[i][j]
            elif last_valid is not None:
                data[i][j] = last_valid

    # bfill
    for j in range(n_cols):
        last_valid = None
        for i in range(n_rows - 1, -1, -1):
            if data[i][j] is not None:
                last_valid = data[i][j]
            elif last_valid is not None:
                data[i][j] = last_valid

    return data

def calc_mean(col):
    return sum(col) / len(col)

def calc_std(col, mean):
    variance = sum((x - mean) ** 2 for x in col) / (len(col) - 1)
    return math.sqrt(variance)

def calc_cov(col1, mean1, col2, mean2):
    return sum((x - mean1) * (y - mean2) for x, y in zip(col1, col2)) / (len(col1) - 1)

def get_minor(matrix, i, j):
    return [row[:j] + row[j+1:] for row in (matrix[:i] + matrix[i+1:])]

def determinant(matrix):
    if len(matrix) == 1:
        return matrix[0][0]
    if len(matrix) == 2:
        return matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0]

    det = 0
    for c in range(len(matrix)):
        det += ((-1)**c) * matrix[0][c] * determinant(get_minor(matrix, 0, c))
    return det

def compute_expected_truth():
    csv_path = '/home/user/sensor_data.csv'
    assert os.path.exists(csv_path), f"Input file {csv_path} is missing."

    header, data = read_csv(csv_path)
    data = ffill_bfill(data)

    n_rows = len(data)
    n_cols = len(header)

    cols = [[data[i][j] for i in range(n_rows)] for j in range(n_cols)]
    means = [calc_mean(col) for col in cols]
    stds = [calc_std(col, mean) for col, mean in zip(cols, means)]

    dropped_rows = []
    cleaned_data = []

    for i, row in enumerate(data):
        is_outlier = False
        for j, val in enumerate(row):
            z_score = abs((val - means[j]) / stds[j])
            if z_score > 3.0:
                is_outlier = True
                break
        if is_outlier:
            dropped_rows.append(i)
        else:
            cleaned_data.append(row)

    n_cleaned = len(cleaned_data)
    cleaned_cols = [[cleaned_data[i][j] for i in range(n_cleaned)] for j in range(n_cols)]
    cleaned_means = [calc_mean(col) for col in cleaned_cols]
    cleaned_stds = [calc_std(col, mean) for col, mean in zip(cleaned_cols, cleaned_means)]

    pairs = []
    for i in range(n_cols):
        for j in range(i + 1, n_cols):
            cov = calc_cov(cleaned_cols[i], cleaned_means[i], cleaned_cols[j], cleaned_means[j])
            corr = cov / (cleaned_stds[i] * cleaned_stds[j])
            if abs(corr) >= 0.90:
                pair = sorted([header[i], header[j]])
                pairs.append(pair)
    pairs.sort()

    cov_matrix = []
    for i in range(n_cols):
        row = []
        for j in range(n_cols):
            cov = calc_cov(cleaned_cols[i], cleaned_means[i], cleaned_cols[j], cleaned_means[j])
            row.append(cov)
        cov_matrix.append(row)

    det = determinant(cov_matrix)
    rounded_det = round(det, 4)

    return {
        "dropped_rows": dropped_rows,
        "correlated_pairs": pairs,
        "cov_determinant": rounded_det
    }

def test_summary_json_exists_and_correct():
    json_path = '/home/user/summary.json'
    assert os.path.exists(json_path), f"Output file {json_path} is missing."

    with open(json_path, 'r') as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON."

    expected_data = compute_expected_truth()

    assert "dropped_rows" in agent_data, "Key 'dropped_rows' missing in JSON output."
    assert agent_data["dropped_rows"] == expected_data["dropped_rows"], \
        f"Expected dropped_rows: {expected_data['dropped_rows']}, got: {agent_data['dropped_rows']}"

    assert "correlated_pairs" in agent_data, "Key 'correlated_pairs' missing in JSON output."
    assert agent_data["correlated_pairs"] == expected_data["correlated_pairs"], \
        f"Expected correlated_pairs: {expected_data['correlated_pairs']}, got: {agent_data['correlated_pairs']}"

    assert "cov_determinant" in agent_data, "Key 'cov_determinant' missing in JSON output."
    agent_det = agent_data["cov_determinant"]
    expected_det = expected_data["cov_determinant"]
    assert isinstance(agent_det, (int, float)), "cov_determinant must be a number."
    assert abs(agent_det - expected_det) <= 0.0001, \
        f"Expected cov_determinant close to {expected_det}, got: {agent_det}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
