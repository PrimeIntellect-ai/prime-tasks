#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess
import sys
from pathlib import Path

import pandas as pd
from sklearn.linear_model import LinearRegression

SCRIPT_PATH = Path('/home/user/train_model.py')
CSV_PATH = Path('/home/user/equipment_stats.csv')
LOG_PATH = Path('/home/user/metrics.log')


def run_submission():
    assert SCRIPT_PATH.exists(), f"File {SCRIPT_PATH} is missing."
    assert SCRIPT_PATH.is_file(), f"File {SCRIPT_PATH} is not a regular file."

    source = SCRIPT_PATH.read_text(encoding='utf-8')
    compile(source, str(SCRIPT_PATH), 'exec')

    if LOG_PATH.exists():
        LOG_PATH.unlink()

    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert LOG_PATH.exists(), f"File {LOG_PATH} does not exist after executing the script."


def get_cleaned_data():
    csv_path = '/home/user/equipment_stats.csv'
    assert os.path.exists(csv_path), f"File {csv_path} is missing."

    temps = []
    pressures = []
    vibrations = []

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            temps.append(float(row['temp']))
            pressures.append(float(row['pressure']) if row['pressure'] else None)
            vibrations.append(float(row['vibration']))

    # 1. Impute missing pressure with median
    valid_p = sorted([p for p in pressures if p is not None])
    mid = len(valid_p) // 2
    if len(valid_p) % 2 == 0:
        median_p = (valid_p[mid - 1] + valid_p[mid]) / 2.0
    else:
        median_p = valid_p[mid]

    for i in range(len(pressures)):
        if pressures[i] is None:
            pressures[i] = median_p

    # 2. Remove rows where temp > 100
    t, p, v = [], [], []
    for i in range(len(temps)):
        if temps[i] <= 100:
            t.append(temps[i])
            p.append(pressures[i])
            v.append(vibrations[i])

    return t, p, v


def compute_pearson_corr(x, y):
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den = math.sqrt(sum((xi - mean_x)**2 for xi in x) * sum((yi - mean_y)**2 for yi in y))
    return num / den


def compute_linear_regression(t, p, v):
    n = len(t)
    sum_t = sum(t)
    sum_p = sum(p)
    sum_t2 = sum(ti**2 for ti in t)
    sum_p2 = sum(pi**2 for pi in p)
    sum_tp = sum(ti*pi for ti, pi in zip(t, p))

    sum_v = sum(v)
    sum_tv = sum(ti*vi for ti, vi in zip(t, v))
    sum_pv = sum(pi*vi for pi, vi in zip(p, v))

    # 3x3 matrix for Normal Equations: X^T X
    m = [
        [sum_t2, sum_tp, sum_t],
        [sum_tp, sum_p2, sum_p],
        [sum_t,  sum_p,  n]
    ]

    # Determinant of 3x3
    det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - \
          m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) + \
          m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])

    # Inverse of 3x3 (only need first two rows for coefficients of t and p)
    inv00 = (m[1][1] * m[2][2] - m[1][2] * m[2][1]) / det
    inv01 = (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / det
    inv02 = (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / det

    inv10 = (m[1][2] * m[2][0] - m[1][0] * m[2][2]) / det
    inv11 = (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / det
    inv12 = (m[0][2] * m[1][0] - m[0][0] * m[1][2]) / det

    coef_t = inv00*sum_tv + inv01*sum_pv + inv02*sum_v
    coef_p = inv10*sum_tv + inv11*sum_pv + inv12*sum_v

    return coef_t, coef_p


def test_metrics_log_contents():
    log_path = '/home/user/metrics.log'
    assert os.path.exists(log_path), f"File {log_path} does not exist. The script may not have run successfully."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {log_path}, but found {len(lines)}."

    t, p, v = get_cleaned_data()

    expected_corr = compute_pearson_corr(t, p)
    expected_coef_t, expected_coef_p = compute_linear_regression(t, p, v)

    expected_line1 = f"{expected_corr:.4f}"
    expected_line2 = f"{expected_coef_t:.4f},{expected_coef_p:.4f}"

    assert lines[0] == expected_line1, f"Line 1 (correlation) mismatch. Expected '{expected_line1}', got '{lines[0]}'."
    assert lines[1] == expected_line2, f"Line 2 (coefficients) mismatch. Expected '{expected_line2}', got '{lines[1]}'."


def write_challenge(rows):
    with CSV_PATH.open('w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['temp', 'pressure', 'vibration'])
        writer.writerows(rows)


def expected_for_rows(rows):
    df = pd.DataFrame(rows, columns=['temp', 'pressure', 'vibration'])
    df['pressure'] = pd.to_numeric(df['pressure'], errors='coerce')
    df['pressure'] = df['pressure'].fillna(df['pressure'].median())
    df = df[df['temp'] <= 100]
    corr = df['temp'].corr(df['pressure'])
    model = LinearRegression()
    model.fit(df[['temp', 'pressure']], df['vibration'])
    return f"{corr:.4f}", f"{model.coef_[0]:.4f},{model.coef_[1]:.4f}"


def verify_challenge(rows):
    expected_line1, expected_line2 = expected_for_rows(rows)
    write_challenge(rows)
    run_submission()

    text = LOG_PATH.read_text(encoding='utf-8')
    lines = text.splitlines()
    assert len(lines) == 2, f"Expected exactly 2 lines in {LOG_PATH}, but found {len(lines)}."
    assert re.fullmatch(r'-?\d+\.\d{4}', lines[0]), f"Invalid correlation format: {lines[0]!r}"
    assert re.fullmatch(r'-?\d+\.\d{4},-?\d+\.\d{4}', lines[1]), f"Invalid coefficient format: {lines[1]!r}"
    assert lines[0] == expected_line1, f"Line 1 mismatch on verification data. Expected '{expected_line1}', got '{lines[0]}'."
    assert lines[1] == expected_line2, f"Line 2 mismatch on verification data. Expected '{expected_line2}', got '{lines[1]}'."


def make_challenge(offset):
    rng = random.SystemRandom()
    t_shift = rng.uniform(-2.0, 2.0) + offset
    p_shift = rng.uniform(-1.5, 1.5)
    temps = [11.0, 19.0, 28.0, 37.0, 49.0, 145.0]
    pressures = [31.0, '', 36.5, 35.0, 43.0, 280.0]
    residuals = [0.4, -0.7, 1.1, -0.2, 0.8, 4.0]
    rows = []
    for i, (temp, pressure, residual) in enumerate(zip(temps, pressures, residuals)):
        temp = temp + t_shift + rng.uniform(-0.2, 0.2)
        if pressure == '':
            vibration = 1.35 * temp + residual + rng.uniform(-0.05, 0.05)
            rows.append([temp, '', vibration])
        else:
            pressure = pressure + p_shift + rng.uniform(-0.2, 0.2)
            vibration = 1.35 * temp - 0.42 * pressure + residual + rng.uniform(-0.05, 0.05)
            rows.append([temp, pressure, vibration])
    return rows


def main():
    assert CSV_PATH.exists(), f"File {CSV_PATH} is missing."
    original_csv = CSV_PATH.read_bytes()

    try:
        # Execute and retain the original verifier's checks against the submitted state.
        run_submission()
        test_metrics_log_contents()

        # Exercise the submitted script on hidden, runtime-generated data. The outlier's
        # pressure affects the median, so this also checks imputation occurs before filtering.
        verify_challenge(make_challenge(0.0))
        verify_challenge(make_challenge(3.0))
    finally:
        CSV_PATH.write_bytes(original_csv)

    # Leave the requested artifact generated from the original dataset.
    run_submission()
    test_metrics_log_contents()


if __name__ == '__main__':
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
