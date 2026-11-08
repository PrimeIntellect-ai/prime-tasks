#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import json
import math

def compute_expected():
    with open('/home/user/sensor_data.csv', 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        data = [(int(row[0]), float(row[1])) for row in reader]

    n = len(data)
    mean_v = sum(v for t, v in data) / n
    std_v = math.sqrt(sum((v - mean_v)**2 for t, v in data) / n)

    anomalies = []
    normal_t = []
    normal_v = []

    for t, v in data:
        if abs(v - mean_v) > 2 * std_v:
            anomalies.append((t, v))
        else:
            normal_t.append(t)
            normal_v.append(v)

    n_normal = len(normal_t)
    mean_nt = sum(normal_t) / n_normal
    mean_nv = sum(normal_v) / n_normal

    numerator = sum((t - mean_nt) * (v - mean_nv) for t, v in zip(normal_t, normal_v))
    denominator = sum((t - mean_nt)**2 for t in normal_t)

    slope = numerator / denominator
    intercept = mean_nv - slope * mean_nt

    return anomalies, slope, intercept

def test_go_module():
    mod_path = '/home/user/etl/go.mod'
    assert os.path.isfile(mod_path), f"{mod_path} does not exist."
    with open(mod_path, 'r') as f:
        content = f.read()
    assert "module etl" in content, f"{mod_path} does not contain 'module etl'."

def test_anomalies_csv():
    expected_anomalies, _, _ = compute_expected()
    anomalies_path = '/home/user/anomalies.csv'
    assert os.path.isfile(anomalies_path), f"{anomalies_path} does not exist."

    with open(anomalies_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['timestamp', 'value'], f"Header in {anomalies_path} is incorrect."
        actual_anomalies = []
        for row in reader:
            actual_anomalies.append((int(row[0]), float(row[1])))

    assert len(actual_anomalies) == len(expected_anomalies), "Number of anomalies does not match expected."

    for actual, expected in zip(actual_anomalies, expected_anomalies):
        assert actual[0] == expected[0], f"Timestamp mismatch: expected {expected[0]}, got {actual[0]}"
        assert math.isclose(actual[1], expected[1], rel_tol=1e-5), f"Value mismatch for timestamp {actual[0]}: expected {expected[1]}, got {actual[1]}"

def test_regression_json():
    _, expected_slope, expected_intercept = compute_expected()
    regression_path = '/home/user/regression.json'
    assert os.path.isfile(regression_path), f"{regression_path} does not exist."

    with open(regression_path, 'r') as f:
        try:
            actual_regression = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{regression_path} is not valid JSON."

    assert "slope" in actual_regression, "'slope' key missing in regression.json."
    assert "intercept" in actual_regression, "'intercept' key missing in regression.json."

    assert math.isclose(actual_regression["slope"], expected_slope, abs_tol=1e-4), \
        f"Slope mismatch: expected {expected_slope}, got {actual_regression['slope']}"
    assert math.isclose(actual_regression["intercept"], expected_intercept, abs_tol=1e-4), \
        f"Intercept mismatch: expected {expected_intercept}, got {actual_regression['intercept']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
