#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def dot(a, b):
    return sum(x * y for x, y in zip(a, b))

def norm(a):
    return math.sqrt(sum(x * x for x in a))

def cos_sim(a, b):
    return dot(a, b) / (norm(a) * norm(b))

def load_csv(path):
    with open(path, 'r') as f:
        lines = f.read().strip().split('\n')
    data = []
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split(',')
        data.append((parts[0], [float(x) for x in parts[1].split()]))
    return data

def get_expected_metrics():
    queries = load_csv('/home/user/data/queries.csv')
    corpus = load_csv('/home/user/data/corpus.csv')

    sim_matrix = []
    for q_id, q_vec in queries:
        row = []
        for c_id, c_vec in corpus:
            row.append((c_id, cos_sim(q_vec, c_vec)))
        sim_matrix.append((q_id, row))

    top_1_A001 = max(sim_matrix[0][1], key=lambda x: x[1])[0]

    top_5_means = {}
    for q_id, row in sim_matrix:
        top5 = sorted(row, key=lambda x: x[1], reverse=True)[:5]
        mean_sim = sum(x[1] for x in top5) / 5.0
        top_5_means[q_id] = mean_sim

    group_A = [v for k, v in top_5_means.items() if k.startswith('A')]
    group_B = [v for k, v in top_5_means.items() if k.startswith('B')]

    mean_A = sum(group_A) / len(group_A)
    mean_B = sum(group_B) / len(group_B)

    # Welch's t-test
    var_A = sum((x - mean_A)**2 for x in group_A) / (len(group_A) - 1)
    var_B = sum((x - mean_B)**2 for x in group_B) / (len(group_B) - 1)
    n_A = len(group_A)
    n_B = len(group_B)

    t_stat = (mean_A - mean_B) / math.sqrt(var_A/n_A + var_B/n_B)
    df = (var_A/n_A + var_B/n_B)**2 / ( (var_A/n_A)**2 / (n_A - 1) + (var_B/n_B)**2 / (n_B - 1) )

    # Numerical integration for t-distribution p-value
    def t_pdf(t, df):
        return math.exp(math.lgamma((df + 1) / 2) - math.lgamma(df / 2)) / math.sqrt(df * math.pi) * (1 + t**2 / df)**(-(df + 1) / 2)

    t_val = abs(t_stat)
    step = 0.001
    area = 0.0
    x = t_val
    # Integrate up to a large enough value
    while x < 50:
        area += t_pdf(x + step/2, df) * step
        x += step
    p_value = area * 2

    return {
        "top_1_item_for_query_A001": top_1_A001,
        "mean_sim_group_A": round(mean_A, 6),
        "mean_sim_group_B": round(mean_B, 6),
        "t_test_p_value": round(p_value, 6)
    }

def test_etl_output_exists_and_valid():
    output_path = '/home/user/etl_output.json'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, 'r') as f:
        try:
            output_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} is not valid JSON.")

    expected = get_expected_metrics()

    assert "top_1_item_for_query_A001" in output_data, "Missing key 'top_1_item_for_query_A001'"
    assert output_data["top_1_item_for_query_A001"] == expected["top_1_item_for_query_A001"], \
        f"Expected top 1 item for A001 to be {expected['top_1_item_for_query_A001']}, got {output_data['top_1_item_for_query_A001']}"

    assert "mean_sim_group_A" in output_data, "Missing key 'mean_sim_group_A'"
    assert math.isclose(output_data["mean_sim_group_A"], expected["mean_sim_group_A"], abs_tol=1e-5), \
        f"Expected mean_sim_group_A near {expected['mean_sim_group_A']}, got {output_data['mean_sim_group_A']}"

    assert "mean_sim_group_B" in output_data, "Missing key 'mean_sim_group_B'"
    assert math.isclose(output_data["mean_sim_group_B"], expected["mean_sim_group_B"], abs_tol=1e-5), \
        f"Expected mean_sim_group_B near {expected['mean_sim_group_B']}, got {output_data['mean_sim_group_B']}"

    assert "t_test_p_value" in output_data, "Missing key 't_test_p_value'"
    # Allow a slightly larger tolerance for p-value due to numerical integration vs scipy
    assert math.isclose(output_data["t_test_p_value"], expected["t_test_p_value"], abs_tol=1e-3), \
        f"Expected t_test_p_value near {expected['t_test_p_value']}, got {output_data['t_test_p_value']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
