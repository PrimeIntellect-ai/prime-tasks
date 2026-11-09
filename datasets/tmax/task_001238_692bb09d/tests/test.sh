#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import pytest

def read_csv(path):
    with open(path, 'r') as f:
        reader = csv.reader(f)
        return [[float(x) for x in row] for row in reader]

def read_target(path):
    rows = read_csv(path)
    if len(rows) == 1:
        return rows[0]
    if all(len(row) == 1 for row in rows):
        return [row[0] for row in rows]
    raise ValueError("Target CSV must represent a single vector")

def mean_cols(data):
    n_rows = len(data)
    n_cols = len(data[0])
    means = [0.0] * n_cols
    for row in data:
        for j in range(n_cols):
            means[j] += row[j]
    return [m / n_rows for m in means]

def dot_product(v1, v2):
    return sum(x * y for x, y in zip(v1, v2))

def vector_norm(v):
    return math.sqrt(sum(x * x for x in v))

def cosine_similarity(v1, v2):
    assert len(v1) == len(v2) == 50
    return dot_product(v1, v2) / (vector_norm(v1) * vector_norm(v2))

def get_cov_diff_norm(data):
    n_rows = len(data)
    n_cols = len(data[0])
    means = mean_cols(data)

    centered = [[data[i][j] - means[j] for j in range(n_cols)] for i in range(n_rows)]

    # cov_np uses N-1, cov_fast uses N
    diff_factor = 1.0 / (n_rows - 1) - 1.0 / n_rows

    diff_norm_sq = 0.0
    for i in range(n_cols):
        for j in range(n_cols):
            dot = sum(centered[k][i] * centered[k][j] for k in range(n_rows))
            diff_val = dot * diff_factor
            diff_norm_sq += diff_val * diff_val

    return math.sqrt(diff_norm_sq)

@pytest.fixture(scope="module")
def expected_results():
    target = read_target('/home/user/target.csv')

    similarities = []
    for i in range(10):
        filename = f'dataset_{i}.csv'
        data = read_csv(f'/home/user/datasets/{filename}')
        mean_vec = mean_cols(data)
        cos_sim = cosine_similarity(mean_vec, target)
        similarities.append((cos_sim, filename, data))

    similarities.sort(key=lambda x: x[0], reverse=True)

    top_3_datasets = [x[1] for x in similarities[:3]]
    best_data = similarities[0][2]

    diff_norm = get_cov_diff_norm(best_data)

    return {
        "top_3_datasets": top_3_datasets,
        "cov_difference_norm": round(diff_norm, 4)
    }

def test_experiment_log_exists():
    assert os.path.isfile('/home/user/experiment_log.json'), "The file /home/user/experiment_log.json does not exist."

def test_experiment_log_contents(expected_results):
    try:
        with open('/home/user/experiment_log.json', 'r') as f:
            log_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("The file /home/user/experiment_log.json is not a valid JSON file.")

    assert "top_3_datasets" in log_data, "The JSON file is missing the 'top_3_datasets' key."
    assert "cov_difference_norm" in log_data, "The JSON file is missing the 'cov_difference_norm' key."

    assert log_data["top_3_datasets"] == expected_results["top_3_datasets"], \
        f"Expected top_3_datasets to be {expected_results['top_3_datasets']}, but got {log_data['top_3_datasets']}."

    assert isinstance(log_data["cov_difference_norm"], (int, float)), \
        "The 'cov_difference_norm' value must be a number."

    assert math.isclose(log_data["cov_difference_norm"], expected_results["cov_difference_norm"], abs_tol=1e-4), \
        f"Expected cov_difference_norm to be {expected_results['cov_difference_norm']}, but got {log_data['cov_difference_norm']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
