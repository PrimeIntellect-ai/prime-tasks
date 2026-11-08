#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import stat
import math
import datetime
import pytest

def parse_iso8601(s):
    try:
        s = s.replace('Z', '+00:00')
        return datetime.datetime.fromisoformat(s)
    except Exception:
        return None

def mat_mult(A, B):
    m = len(A)
    n = len(A[0])
    p = len(B[0])
    C = [[0]*p for _ in range(m)]
    for i in range(m):
        for j in range(p):
            for k in range(n):
                C[i][j] += A[i][k] * B[k][j]
    return C

def mat_add(A, B):
    return [[A[i][j] + B[i][j] for j in range(len(A[0]))] for i in range(len(A))]

def mat_sub(A, B):
    return [[A[i][j] - B[i][j] for j in range(len(A[0]))] for i in range(len(A))]

def mat_inv_2x2(A):
    det = A[0][0]*A[1][1] - A[0][1]*A[1][0]
    return [[A[1][1]/det, -A[0][1]/det], [-A[1][0]/det, A[0][0]/det]]

def get_expected_estimates():
    raw_file = "/home/user/data/raw_sensors.csv"
    if not os.path.exists(raw_file):
        return []

    valid_data = []
    with open(raw_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts_str = row['timestamp']
            dt = parse_iso8601(ts_str)
            if dt is None:
                continue
            try:
                sensor_id = int(row['sensor_id'])
                temp = float(row['temperature_raw'])
                pres = float(row['pressure_raw'])
            except ValueError:
                continue

            if not (1 <= sensor_id <= 10):
                continue
            if not (-50.0 <= temp <= 150.0):
                continue
            if not (0.0 <= pres <= 200.0):
                continue

            valid_data.append({'dt': dt, 'temp': temp, 'pres': pres})

    # Group by 1-hour tumbling windows
    windows = {}
    for item in valid_data:
        dt = item['dt']
        window_start = dt.replace(minute=0, second=0, microsecond=0)
        ws_str = window_start.strftime("%Y-%m-%d %H:%M:%S")
        if ws_str not in windows:
            windows[ws_str] = {'temps': [], 'press': []}
        windows[ws_str]['temps'].append(item['temp'])
        windows[ws_str]['press'].append(item['pres'])

    sorted_windows = sorted(windows.keys())

    # Bayesian Update
    x = [[20.0], [100.0]]
    P = [[10.0, 0.0], [0.0, 10.0]]
    R = [[2.0, 0.5], [0.5, 3.0]]
    I = [[1.0, 0.0], [0.0, 1.0]]

    results = []
    for ws in sorted_windows:
        z_t = [
            [sum(windows[ws]['temps']) / len(windows[ws]['temps'])],
            [sum(windows[ws]['press']) / len(windows[ws]['press'])]
        ]

        # K_t = P_t-1 * (P_t-1 + R)^-1
        P_plus_R = mat_add(P, R)
        P_plus_R_inv = mat_inv_2x2(P_plus_R)
        K = mat_mult(P, P_plus_R_inv)

        # x_t = x_t-1 + K_t * (z_t - x_t-1)
        z_minus_x = mat_sub(z_t, x)
        K_times_diff = mat_mult(K, z_minus_x)
        x = mat_add(x, K_times_diff)

        # P_t = (I - K_t) * P_t-1
        I_minus_K = mat_sub(I, K)
        P = mat_mult(I_minus_K, P)

        results.append({
            'window_start': ws,
            'est_temperature': round(x[0][0], 4),
            'est_pressure': round(x[1][0], 4)
        })

    return results

def test_run_pipeline_script():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.exists(script_path), f"Missing {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable"

def test_venv_exists():
    venv_path = "/home/user/venv"
    assert os.path.isdir(venv_path), f"Virtual environment directory {venv_path} is missing"
    assert os.path.exists(os.path.join(venv_path, "bin", "python")) or os.path.exists(os.path.join(venv_path, "bin", "python3")), "Python executable not found in venv"

def test_pipeline_script_exists():
    assert os.path.exists("/home/user/pipeline.py"), "Missing /home/user/pipeline.py"

def test_output_file_exists():
    output_path = "/home/user/output/estimates.csv"
    assert os.path.exists(output_path), f"Missing output file {output_path}"

def test_output_content():
    output_path = "/home/user/output/estimates.csv"
    if not os.path.exists(output_path):
        pytest.fail("Output file missing, cannot test content.")

    expected_results = get_expected_estimates()

    with open(output_path, 'r') as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    assert reader.fieldnames == ["window_start", "est_temperature", "est_pressure"], f"Invalid columns in {output_path}"
    assert len(actual_rows) == len(expected_results), f"Expected {len(expected_results)} rows, got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_results)):
        assert actual['window_start'] == expected['window_start'], f"Row {i}: window_start mismatch"
        assert math.isclose(float(actual['est_temperature']), expected['est_temperature'], abs_tol=1e-3), \
            f"Row {i}: est_temperature mismatch. Expected {expected['est_temperature']}, got {actual['est_temperature']}"
        assert math.isclose(float(actual['est_pressure']), expected['est_pressure'], abs_tol=1e-3), \
            f"Row {i}: est_pressure mismatch. Expected {expected['est_pressure']}, got {actual['est_pressure']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
