#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import glob
import subprocess
import sys
import pytest

HOME = "/home/user"
REPORT_PATH = os.path.join(HOME, "integration_report.json")
DATA_PATH = os.path.join(HOME, "training_data.csv")


def run_submission_script():
    candidates = glob.glob(os.path.join(HOME, "**", "*.py"), recursive=True)
    preferred = os.path.join(HOME, "process_data.py")
    candidates = sorted(set(candidates), key=lambda p: (p != preferred, p))
    assert candidates, "No Python integration script was found under /home/user."

    diagnostics = []
    for script in candidates:
        for output in (REPORT_PATH, DATA_PATH):
            if os.path.exists(output):
                os.remove(output)
        try:
            result = subprocess.run(
                [sys.executable, script],
                cwd=HOME,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=60,
            )
        except subprocess.TimeoutExpired:
            diagnostics.append(f"{script}: timed out")
            continue

        if result.returncode == 0 and os.path.isfile(REPORT_PATH) and os.path.isfile(DATA_PATH):
            return
        diagnostics.append(
            f"{script}: exit={result.returncode}, report={os.path.isfile(REPORT_PATH)}, "
            f"csv={os.path.isfile(DATA_PATH)}, stderr={result.stderr[-500:]}"
        )

    pytest.fail("No Python script ran successfully and produced both required outputs. " + " | ".join(diagnostics))


run_submission_script()


def load_and_validate_inputs():
    raw_path = os.path.join(HOME, "raw_sensor.csv")
    ref_path = os.path.join(HOME, "reference_trajectory.csv")

    with open(raw_path, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['t', 'a']
        raw = [(float(r['t']), float(r['a'])) for r in reader]

    with open(ref_path, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['t', 'v_ref', 'p_ref']
        ref = [(float(r['t']), float(r['v_ref']), float(r['p_ref'])) for r in reader]

    assert len(raw) == 101, "raw_sensor.csv must retain all 101 supplied samples"
    assert len(ref) == 21, "reference_trajectory.csv must retain all 21 supplied samples"

    for i, (t, a) in enumerate(raw):
        expected_t = round(i * 0.1, 2)
        assert math.isclose(t, expected_t, abs_tol=1e-12)
        assert math.isclose(a, math.sin(expected_t), rel_tol=1e-12, abs_tol=1e-12)

    for i, (t, v, p) in enumerate(ref):
        expected_t = round(i * 0.1, 2)
        assert math.isclose(t, expected_t, abs_tol=1e-12)
        assert math.isclose(v, 1.0 - math.cos(expected_t), rel_tol=1e-12, abs_tol=1e-12)
        assert math.isclose(p, expected_t - math.sin(expected_t), rel_tol=1e-12, abs_tol=1e-12)

    return raw, ref


def compute_expected():
    raw, ref = load_and_validate_inputs()
    n = len(raw)
    euler_v = [0.0] * n
    euler_p = [0.0] * n
    trapz_v = [0.0] * n
    trapz_p = [0.0] * n

    for i in range(n - 1):
        dt = raw[i + 1][0] - raw[i][0]
        a_i = raw[i][1]
        a_next = raw[i + 1][1]
        euler_v[i + 1] = euler_v[i] + a_i * dt
        euler_p[i + 1] = euler_p[i] + euler_v[i] * dt
        trapz_v[i + 1] = trapz_v[i] + (a_i + a_next) * 0.5 * dt
        trapz_p[i + 1] = trapz_p[i] + (trapz_v[i] + trapz_v[i + 1]) * 0.5 * dt

    raw_index = {round(t, 10): i for i, (t, _) in enumerate(raw)}
    matches = [(raw_index[round(t, 10)], v, p) for t, v, p in ref]

    def mse(values, reference_position):
        return sum((values[i] - row[reference_position]) ** 2 for i, *row in matches) / len(matches)

    expected_report = {
        'euler_mse_v': mse(euler_v, 0),
        'euler_mse_p': mse(euler_p, 1),
        'trapz_mse_v': mse(trapz_v, 0),
        'trapz_mse_p': mse(trapz_p, 1),
    }
    euler_combined = expected_report['euler_mse_v'] + expected_report['euler_mse_p']
    trapz_combined = expected_report['trapz_mse_v'] + expected_report['trapz_mse_p']
    expected_report['best_method'] = 'euler' if euler_combined < trapz_combined else 'trapz'

    trajectories = {
        'euler': (euler_v, euler_p),
        'trapz': (trapz_v, trapz_p),
    }
    return raw, expected_report, trajectories


EXPECTED_RAW, EXPECTED_REPORT, TRAJECTORIES = compute_expected()


def test_integration_report_json():
    report_path = "/home/user/integration_report.json"
    assert os.path.isfile(report_path), f"Missing required output file: {report_path}"

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    expected_keys = {"euler_mse_v", "euler_mse_p", "trapz_mse_v", "trapz_mse_p", "best_method"}
    assert expected_keys.issubset(data.keys()), f"Missing keys in {report_path}. Expected {expected_keys}, found {set(data.keys())}"

    assert data["best_method"] == "trapz", f"Expected best_method to be 'trapz', got {data['best_method']}"
    assert data["trapz_mse_v"] < data["euler_mse_v"], "Trapezoidal MSE for velocity should be less than Euler MSE."
    assert data["trapz_mse_p"] < data["euler_mse_p"], "Trapezoidal MSE for position should be less than Euler MSE."

    for key in ('euler_mse_v', 'euler_mse_p', 'trapz_mse_v', 'trapz_mse_p'):
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), f"{key} must be numeric"
        assert math.isfinite(data[key]), f"{key} must be finite"
        assert math.isclose(data[key], EXPECTED_REPORT[key], rel_tol=1e-7, abs_tol=1e-12), \
            f"Incorrect {key}: expected {EXPECTED_REPORT[key]}, got {data[key]}"
    assert data['best_method'] == EXPECTED_REPORT['best_method']


def test_training_data_csv():
    data_path = "/home/user/training_data.csv"
    assert os.path.isfile(data_path), f"Missing required output file: {data_path}"

    with open(data_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['t', 'a', 'v', 'p'], f"Incorrect header in {data_path}. Expected ['t', 'a', 'v', 'p'], got {header}"

        rows = list(reader)
        assert len(rows) == 101, f"Expected 101 data rows in {data_path}, got {len(rows)}"

        last_row = rows[-1]
        t_val = float(last_row[0])
        a_val = float(last_row[1])
        v_val = float(last_row[2])
        p_val = float(last_row[3])

        assert math.isclose(t_val, 10.0, abs_tol=1e-3), f"Expected last row t=10.0, got {t_val}"

        for val_str in last_row:
            if '.' in val_str:
                decimals = len(val_str.split('.')[1])
                assert decimals <= 4, f"Values should be rounded to 4 decimal places, found {val_str}"

        expected_a = math.sin(10.0)
        expected_v = 1.0 - math.cos(10.0)
        expected_p = 10.0 - math.sin(10.0)

        assert math.isclose(a_val, expected_a, abs_tol=0.1), f"Acceleration at t=10.0 incorrect: {a_val}"
        assert math.isclose(v_val, expected_v, abs_tol=0.1), f"Velocity at t=10.0 incorrect: {v_val}"
        assert math.isclose(p_val, expected_p, abs_tol=0.1), f"Position at t=10.0 incorrect: {p_val}"

    expected_v_values, expected_p_values = TRAJECTORIES[EXPECTED_REPORT['best_method']]
    for i, row in enumerate(rows):
        assert len(row) == 4, f"Row {i + 2} must contain exactly four columns"
        for value in row:
            if '.' in value:
                assert len(value.split('.', 1)[1]) <= 4, f"Values should be rounded to 4 decimal places, found {value}"
        try:
            actual = [float(value) for value in row]
        except ValueError:
            pytest.fail(f"Row {i + 2} contains a non-numeric value: {row}")
        assert all(math.isfinite(value) for value in actual), f"Row {i + 2} contains a non-finite value"

        expected = [
            round(EXPECTED_RAW[i][0], 4),
            round(EXPECTED_RAW[i][1], 4),
            round(expected_v_values[i], 4),
            round(expected_p_values[i], 4),
        ]
        for column, got, want in zip(('t', 'a', 'v', 'p'), actual, expected):
            assert math.isclose(got, want, rel_tol=0.0, abs_tol=5e-5), \
                f"Incorrect {column} at row {i + 2}: expected {want}, got {got}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
