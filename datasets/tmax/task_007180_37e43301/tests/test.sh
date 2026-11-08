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

def compute_expected_values():
    users = {}
    with open('/home/user/users.csv', 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = row['user_id'].strip()
            users[uid] = row['group'].strip()

    group_a = []
    group_b = []
    with open('/home/user/sessions.csv', 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = row['user_id'].strip()
            if uid in users:
                dur = float(row['duration'])
                if users[uid] == 'A':
                    group_a.append(dur)
                elif users[uid] == 'B':
                    group_b.append(dur)

    mean_a = sum(group_a) / len(group_a)
    mean_b = sum(group_b) / len(group_b)

    var_a = sum((x - mean_a)**2 for x in group_a) / (len(group_a) - 1)
    var_b = sum((x - mean_b)**2 for x in group_b) / (len(group_b) - 1)

    diff_means = mean_b - mean_a
    se = math.sqrt((var_a / len(group_a)) + (var_b / len(group_b)))

    ci_lower = diff_means - 1.96 * se
    ci_upper = diff_means + 1.96 * se

    return round(diff_means, 4), round(ci_lower, 4), round(ci_upper, 4)

def test_results_json_exists():
    assert os.path.isfile('/home/user/results.json'), "The file /home/user/results.json was not found. Did the Go program run successfully?"

def test_results_json_values():
    try:
        with open('/home/user/results.json', 'r', encoding='utf-8') as f:
            results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("/home/user/results.json is not a valid JSON file.")

    assert "diff_means" in results, "Key 'diff_means' missing in results.json"
    assert "ci_lower" in results, "Key 'ci_lower' missing in results.json"
    assert "ci_upper" in results, "Key 'ci_upper' missing in results.json"

    exp_diff, exp_lower, exp_upper = compute_expected_values()

    tol = 0.0002
    assert abs(results["diff_means"] - exp_diff) <= tol, f"diff_means is {results['diff_means']}, expected ~{exp_diff}"
    assert abs(results["ci_lower"] - exp_lower) <= tol, f"ci_lower is {results['ci_lower']}, expected ~{exp_lower}"
    assert abs(results["ci_upper"] - exp_upper) <= tol, f"ci_upper is {results['ci_upper']}, expected ~{exp_upper}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
