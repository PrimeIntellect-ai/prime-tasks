#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import re
import pytest
import numpy as np

def get_euclidean_distance(p1, p2):
    return math.hypot(p1[0] - p2[0], p1[1] - p2[1])

def compute_expected_densities():
    nodes_path = '/home/user/nodes.csv'
    defects_path = '/home/user/defects.csv'

    assert os.path.isfile(nodes_path), f"Missing {nodes_path}"
    assert os.path.isfile(defects_path), f"Missing {defects_path}"

    nodes = []
    with open(nodes_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nodes.append((float(row['x']), float(row['y'])))

    defects = []
    with open(defects_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            defects.append((float(row['x']), float(row['y'])))

    densities = []
    for dp in defects:
        sub_nodes = [node for node in nodes if get_euclidean_distance(node, dp) < 5.0]
        v = len(sub_nodes)

        if v < 2:
            densities.append(0.0)
            continue

        edges = 0
        for i in range(v):
            for j in range(i + 1, v):
                if get_euclidean_distance(sub_nodes[i], sub_nodes[j]) < 1.5:
                    edges += 1

        densities.append((2.0 * edges) / (v * (v - 1)))

    return densities

def compute_expected_bootstrap_ci(densities):
    values = np.asarray(densities, dtype=float)
    np.random.seed(42)
    bootstrap_means = []
    for _ in range(10000):
        sample = np.random.choice(values, size=len(values), replace=True)
        bootstrap_means.append(float(np.mean(sample)))
    lower, upper = np.percentile(bootstrap_means, [2.5, 97.5])
    return round(float(lower), 4), round(float(upper), 4)

def test_baseline_ci_json():
    json_path = '/home/user/baseline_ci.json'
    assert os.path.isfile(json_path), f"Output file {json_path} is missing."

    with open(json_path, 'r') as f:
        raw_json = f.read()

    try:
        result = json.loads(raw_json)
    except json.JSONDecodeError:
        pytest.fail(f"File {json_path} does not contain valid JSON.")

    assert isinstance(result, dict), "JSON output must be an object."
    assert "lower_bound" in result, "Key 'lower_bound' missing in JSON output."
    assert "upper_bound" in result, "Key 'upper_bound' missing in JSON output."
    assert set(result) == {"lower_bound", "upper_bound"}, \
        "JSON output must contain exactly the required keys."

    lower = result["lower_bound"]
    upper = result["upper_bound"]

    assert isinstance(lower, (int, float)) and not isinstance(lower, bool), \
        "'lower_bound' must be a number."
    assert isinstance(upper, (int, float)) and not isinstance(upper, bool), \
        "'upper_bound' must be a number."
    assert math.isfinite(lower) and math.isfinite(upper), "CI bounds must be finite."
    assert lower <= upper, "'lower_bound' should not be greater than 'upper_bound'."

    # Require each JSON number to be written with exactly four digits after the decimal.
    for key in ("lower_bound", "upper_bound"):
        matches = re.findall(
            rf'"{key}"\s*:\s*(-?(?:0|[1-9]\d*)\.\d{{4}})(?=\s*[,}}])',
            raw_json,
        )
        assert len(matches) == 1, f"'{key}' must be written with exactly 4 decimal places."

    densities = compute_expected_densities()
    n = len(densities)
    assert n > 0, "No defects found to compute densities."

    mean_density = sum(densities) / n
    variance = sum((x - mean_density) ** 2 for x in densities) / n
    std_error = math.sqrt(variance / n)

    approx_lower = mean_density - 1.96 * std_error
    approx_upper = mean_density + 1.96 * std_error

    assert math.isclose(lower, approx_lower, abs_tol=0.05), \
        f"lower_bound {lower} is too far from the expected approximate value {approx_lower:.4f}"
    assert math.isclose(upper, approx_upper, abs_tol=0.05), \
        f"upper_bound {upper} is too far from the expected approximate value {approx_upper:.4f}"
    assert lower <= mean_density <= upper, \
        f"The computed mean density ({mean_density:.4f}) is not within the reported CI [{lower}, {upper}]."

    expected_lower, expected_upper = compute_expected_bootstrap_ci(densities)
    assert lower == expected_lower, \
        f"lower_bound {lower} does not match the seeded percentile bootstrap result {expected_lower:.4f}"
    assert upper == expected_upper, \
        f"upper_bound {upper} does not match the seeded percentile bootstrap result {expected_upper:.4f}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
