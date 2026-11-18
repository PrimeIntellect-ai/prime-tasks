#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import json
import pytest

RAW_OBS_PATH = '/home/user/raw_obs.csv'
JSON_RESULTS_PATH = '/home/user/model_results.json'
CSV_PLOT_PATH = '/home/user/clean_plot_data.csv'

def compute_expected_data():
    filtered = []
    with open(RAW_OBS_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['sensor_status'] == 'OK' and float(row['altitude_m']) >= 0:
                filtered.append((float(row['altitude_m']), float(row['pressure_hpa'])))

    filtered.sort(key=lambda x: x[0])

    x = [d[0] for d in filtered]
    y = [math.log(d[1]) for d in filtered]
    n = len(x)
    sum_x = sum(x)
    sum_y = sum(y)
    sum_xy = sum(x[i]*y[i] for i in range(n))
    sum_xx = sum(x[i]*x[i] for i in range(n))

    slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x)
    intercept = (sum_y - slope * sum_x) / n

    P0 = math.exp(intercept)
    H = -1.0 / slope

    return round(P0, 2), round(H, 2), filtered

def test_json_results():
    """Test that the model_results.json file contains the correct P0 and H values."""
    assert os.path.exists(JSON_RESULTS_PATH), f"File {JSON_RESULTS_PATH} does not exist."

    with open(JSON_RESULTS_PATH, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_RESULTS_PATH} is not a valid JSON file.")

    expected_P0, expected_H, _ = compute_expected_data()

    assert "P0" in results, "Key 'P0' is missing from model_results.json."
    assert "H" in results, "Key 'H' is missing from model_results.json."

    assert math.isclose(results["P0"], expected_P0, rel_tol=1e-4), f"Expected P0 to be {expected_P0}, got {results['P0']}."
    assert math.isclose(results["H"], expected_H, rel_tol=1e-4), f"Expected H to be {expected_H}, got {results['H']}."

def test_clean_plot_data():
    """Test that clean_plot_data.csv has the correct format and values."""
    assert os.path.exists(CSV_PLOT_PATH), f"File {CSV_PLOT_PATH} does not exist."

    expected_P0, expected_H, filtered = compute_expected_data()

    with open(CSV_PLOT_PATH, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)

        expected_header = ['altitude_m', 'actual_pressure', 'predicted_pressure']
        assert header == expected_header, f"Expected header {expected_header}, got {header}."

        rows = list(reader)
        assert len(rows) == len(filtered), f"Expected {len(filtered)} rows, got {len(rows)}."

        for i, (row, (alt, act_p)) in enumerate(zip(rows, filtered)):
            try:
                out_alt = float(row[0])
                out_act = float(row[1])
                out_pred = float(row[2])
            except ValueError:
                pytest.fail(f"Row {i+1} in {CSV_PLOT_PATH} contains non-numeric values: {row}")

            expected_pred = expected_P0 * math.exp(-alt / expected_H)

            assert math.isclose(out_alt, alt, rel_tol=1e-4), f"Row {i+1}: Expected altitude {alt}, got {out_alt}."
            assert math.isclose(out_act, act_p, rel_tol=1e-4), f"Row {i+1}: Expected actual pressure {act_p}, got {out_act}."
            assert math.isclose(out_pred, round(expected_pred, 2), rel_tol=1e-2), f"Row {i+1}: Expected predicted pressure {round(expected_pred, 2)}, got {out_pred}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
