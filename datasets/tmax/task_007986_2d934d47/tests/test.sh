#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os

import numpy as np
import pandas as pd
import pytest
from scipy.stats import wasserstein_distance

INITIAL_PATH = "/home/user/initial_data.csv"
REFINED_PATH = "/home/user/refined_data.csv"
REPORT_PATH = "/home/user/report.json"


def load_and_validate_initial_data():
    # Recreate the setup data independently so replacing the task input cannot
    # influence the expected answer.
    np.random.seed(10)
    n = 400
    expected_x = np.random.uniform(0, 1, n)
    expected_y = np.random.uniform(0, 1, n)
    expected_value = np.sin(2 * np.pi * expected_x) * np.cos(2 * np.pi * expected_y)
    noise = np.random.normal(0, 0.1, n)
    mask15 = (expected_x > 0.75) & (expected_y > 0.75)
    mask3 = (expected_x < 0.25) & (expected_y > 0.75)
    noise[mask15] += np.random.normal(0, 0.8, int(mask15.sum()))
    noise[mask3] += np.random.normal(0, 0.6, int(mask3.sum()))
    expected_value += noise

    assert os.path.exists(INITIAL_PATH), "initial_data.csv is missing"
    actual = pd.read_csv(INITIAL_PATH)
    assert list(actual.columns) == ["x", "y", "value"]
    assert len(actual) == 400
    actual_values = actual[["x", "y", "value"]].to_numpy(dtype=float)
    canonical_values = np.column_stack((expected_x, expected_y, expected_value))
    np.testing.assert_allclose(actual_values, canonical_values, rtol=1e-14, atol=1e-14)
    return actual


def compute_expected():
    initial = load_and_validate_initial_data()
    x = initial["x"].to_numpy(dtype=float)
    y = initial["y"].to_numpy(dtype=float)
    values = initial["value"].to_numpy(dtype=float)
    cell_indices = np.minimum((x * 4).astype(int), 3) * 4 + np.minimum((y * 4).astype(int), 3)

    np.random.seed(42)
    refined_subdomains = []
    cell_values = {}
    for idx in range(16):
        vals = values[cell_indices == idx]
        cell_values[idx] = vals
        assert len(vals) > 0, f"Unexpected empty input subdomain {idx}"
        bootstrap_means = np.empty(1000, dtype=float)
        for sample_idx in range(1000):
            bootstrap_means[sample_idx] = np.mean(
                np.random.choice(vals, size=len(vals), replace=True)
            )
        low, high = np.percentile(bootstrap_means, [2.5, 97.5])
        if high - low > 0.2:
            refined_subdomains.append(idx)

    generated_blocks = []
    for idx in refined_subdomains:
        i, j = divmod(idx, 4)
        new_x = np.random.uniform(i * 0.25, (i + 1) * 0.25, 50)
        new_y = np.random.uniform(j * 0.25, (j + 1) * 0.25, 50)
        new_value = np.random.choice(cell_values[idx], size=50, replace=True)
        generated_blocks.append(np.column_stack((new_x, new_y, new_value)))

    original_block = initial[["x", "y", "value"]].to_numpy(dtype=float)
    if generated_blocks:
        expected_rows = np.vstack([original_block] + generated_blocks)
    else:
        expected_rows = original_block.copy()

    expected_distance = float(wasserstein_distance(values, expected_rows[:, 2]))
    return refined_subdomains, expected_rows, expected_distance


def load_report():
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not valid JSON")


def test_files_exist():
    assert os.path.exists(REFINED_PATH), "refined_data.csv is missing"
    assert os.path.exists(REPORT_PATH), "report.json is missing"


def test_report_structure_and_types():
    report = load_report()
    assert set(report.keys()) == {
        "refined_subdomains",
        "wasserstein_distance",
        "final_point_count",
    }, "report.json must contain exactly the required keys"

    assert isinstance(report["refined_subdomains"], list), "'refined_subdomains' must be a list"
    for item in report["refined_subdomains"]:
        assert isinstance(item, int), "Items in 'refined_subdomains' must be integers"

    assert isinstance(report["wasserstein_distance"], (int, float)), "'wasserstein_distance' must be a float"
    assert math.isfinite(float(report["wasserstein_distance"])), "'wasserstein_distance' must be finite"
    assert isinstance(report["final_point_count"], int), "'final_point_count' must be an integer"


def test_report_logic_and_computed_results():
    report = load_report()
    expected_domains, expected_rows, expected_distance = compute_expected()

    refined_subdomains = report["refined_subdomains"]
    final_point_count = report["final_point_count"]

    assert refined_subdomains == sorted(refined_subdomains), "'refined_subdomains' must be in ascending order"
    expected_count_from_report = 400 + 50 * len(refined_subdomains)
    assert final_point_count == expected_count_from_report, (
        f"Expected final_point_count to be {expected_count_from_report}, got {final_point_count}"
    )
    assert 3 in refined_subdomains, "Subdomain 3 was expected to be refined due to injected high variance but is missing."
    assert 15 in refined_subdomains, "Subdomain 15 was expected to be refined due to injected high variance but is missing."

    assert refined_subdomains == expected_domains, (
        f"Expected refined_subdomains {expected_domains}, got {refined_subdomains}"
    )
    assert final_point_count == len(expected_rows)
    assert math.isclose(
        float(report["wasserstein_distance"]), expected_distance,
        rel_tol=1e-12, abs_tol=1e-12,
    ), f"Incorrect Wasserstein distance: expected {expected_distance}"


def test_refined_data_csv():
    report = load_report()
    expected_domains, expected_rows, expected_distance = compute_expected()

    with open(REFINED_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("refined_data.csv is empty")
        assert header == ["x", "y", "value"], f"Expected header ['x', 'y', 'value'], got {header}"
        raw_rows = list(reader)

    assert len(raw_rows) == report["final_point_count"], (
        f"refined_data.csv has {len(raw_rows)} rows, expected {report['final_point_count']} based on report.json"
    )
    assert all(len(row) == 3 for row in raw_rows), "Every CSV row must have exactly three fields"

    try:
        actual_rows = np.asarray([[float(v) for v in row] for row in raw_rows], dtype=float)
    except (TypeError, ValueError):
        pytest.fail("All refined_data.csv fields must be numeric")
    assert np.isfinite(actual_rows).all(), "refined_data.csv contains non-finite values"
    assert actual_rows.shape == expected_rows.shape
    np.testing.assert_allclose(actual_rows, expected_rows, rtol=1e-12, atol=1e-12)

    actual_distance = float(wasserstein_distance(expected_rows[:400, 2], actual_rows[:, 2]))
    assert math.isclose(actual_distance, expected_distance, rel_tol=1e-12, abs_tol=1e-12)
    assert math.isclose(
        float(report["wasserstein_distance"]), actual_distance,
        rel_tol=1e-12, abs_tol=1e-12,
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
