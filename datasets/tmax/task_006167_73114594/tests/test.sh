#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import csv
import json
import math
import os
import statistics
import pytest
from scipy.stats import t as student_t

def test_results_json_exists_and_valid():
    """Test that results.json exists and is valid JSON."""
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"Missing {results_path}"

    with open(results_path, 'r') as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not a valid JSON file")

def test_results_json_contents():
    """Test the contents of results.json against the expected computed values."""
    results_path = "/home/user/results.json"
    raw_path = "/home/user/raw_sensors.csv"
    baseline_path = "/home/user/baseline_predictions.csv"

    assert os.path.isfile(raw_path), f"Missing {raw_path}"
    assert os.path.isfile(baseline_path), f"Missing {baseline_path}"

    with open(results_path, 'r') as f:
        actual = json.load(f)

    # Read raw_sensors.csv
    rows = []
    with open(raw_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    # Step 1: Filter temp
    cleaned = []
    for r in rows:
        if not r['temp']:
            continue
        temp = float(r['temp'])
        if temp < -50 or temp > 150:
            continue
        cleaned.append(r)

    # Step 2: Calculate medians for pressure per sensor_id
    sensor_pressures = {}
    for r in cleaned:
        sid = r['sensor_id']
        if sid not in sensor_pressures:
            sensor_pressures[sid] = []
        if r['pressure']:
            sensor_pressures[sid].append(float(r['pressure']))

    medians = {sid: statistics.median(vals) for sid, vals in sensor_pressures.items()}

    # Step 3: Calculate mean for humidity
    humidities = [float(r['humidity']) for r in cleaned if r['humidity']]
    mean_hum = statistics.mean(humidities)

    # Step 4: Compute power_output
    powers = []
    s1_powers = []
    s2_powers = []
    power_map = {}

    for r in cleaned:
        temp = float(r['temp'])
        pressure = float(r['pressure']) if r['pressure'] else medians[r['sensor_id']]
        humidity = float(r['humidity']) if r['humidity'] else mean_hum

        pwr = 0.5 * temp + 0.2 * pressure - 0.1 * humidity + 5.0
        powers.append(pwr)

        if r['sensor_id'] == 'S1':
            s1_powers.append(pwr)
        elif r['sensor_id'] == 'S2':
            s2_powers.append(pwr)

        key = (r['timestamp'], r['sensor_id'])
        power_map[key] = pwr

    # Step 5: Compute MSE
    sq_errors = []
    with open(baseline_path, 'r') as f:
        reader = csv.DictReader(f)
        for r in reader:
            key = (r['timestamp'], r['sensor_id'])
            if key in power_map:
                diff = power_map[key] - float(r['power_output'])
                sq_errors.append(diff * diff)

    mse = sum(sq_errors) / len(sq_errors) if sq_errors else 0.0

    # Step 6: Compute Welch's t-test statistic and two-sided p-value
    n1 = len(s1_powers)
    n2 = len(s2_powers)
    mean1 = statistics.mean(s1_powers)
    mean2 = statistics.mean(s2_powers)
    var1 = statistics.variance(s1_powers)
    var2 = statistics.variance(s2_powers)

    term1 = var1 / n1
    term2 = var2 / n2
    t_stat = (mean1 - mean2) / math.sqrt(term1 + term2)
    degrees_of_freedom = ((term1 + term2) ** 2) / (
        (term1 ** 2) / (n1 - 1) + (term2 ** 2) / (n2 - 1)
    )
    p_value = 2.0 * student_t.sf(abs(t_stat), degrees_of_freedom)

    # Validate JSON values
    assert "clean_row_count" in actual, "Missing key 'clean_row_count'"
    assert actual["clean_row_count"] == len(cleaned), f"clean_row_count: expected {len(cleaned)}, got {actual['clean_row_count']}"

    assert "mean_power" in actual, "Missing key 'mean_power'"
    expected_mean_power = statistics.mean(powers)
    assert math.isclose(actual["mean_power"], expected_mean_power, abs_tol=0.001), f"mean_power: expected {expected_mean_power:.4f}, got {actual['mean_power']}"

    assert "mse" in actual, "Missing key 'mse'"
    assert math.isclose(actual["mse"], mse, abs_tol=0.001), f"mse: expected {mse:.4f}, got {actual['mse']}"

    assert "t_stat" in actual, "Missing key 't_stat'"
    assert math.isclose(actual["t_stat"], t_stat, abs_tol=0.001), f"t_stat: expected {t_stat:.4f}, got {actual['t_stat']}"

    assert "p_value" in actual, "Missing key 'p_value'"
    assert isinstance(actual["p_value"], (int, float)), "p_value must be a numerical value"
    assert math.isfinite(actual["p_value"]), "p_value must be finite"
    assert math.isclose(actual["p_value"], p_value, abs_tol=0.001), f"p_value: expected {p_value:.4f}, got {actual['p_value']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
