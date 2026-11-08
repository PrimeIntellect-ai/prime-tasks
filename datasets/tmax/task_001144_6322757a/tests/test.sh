#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import csv
import subprocess
from pathlib import Path

import numpy as np
import pytest

HOME = Path('/home/user')


def b_exact(times, k1, k2):
    times = np.asarray(times, dtype=float)
    if abs(k2 - k1) < 1e-12:
        return 100.0 * k1 * times * np.exp(-k1 * times)
    return (k1 * 100.0 / (k2 - k1)) * (np.exp(-k1 * times) - np.exp(-k2 * times))


def load_params(path=HOME / 'best_params.json'):
    with open(path) as f:
        return json.load(f)


def load_curve(path=HOME / 'best_fit_curve.csv'):
    with open(path, newline='') as f:
        rows = list(csv.reader(f))
    assert rows[0] == ['time', 'B_num']
    values = np.asarray([[float(x), float(y)] for x, y in rows[1:]], dtype=float)
    assert np.all(np.isfinite(values))
    return values[:, 0], values[:, 1]


def monte_carlo_candidates(times, observations):
    """Compute the optimum for both conventional interpretations of pair generation."""
    times = np.asarray(times, dtype=float)
    observations = np.asarray(observations, dtype=float)
    candidates = []

    rng = np.random.RandomState(42)
    candidates.append((rng.uniform(0.1, 1.0, 100000),
                       rng.uniform(0.1, 1.0, 100000)))

    rng = np.random.RandomState(42)
    pairs = rng.uniform(0.1, 1.0, (100000, 2))
    candidates.append((pairs[:, 0], pairs[:, 1]))

    winners = []
    for k1s, k2s in candidates:
        best_mse = float('inf')
        best_pair = None
        for start in range(0, 100000, 5000):
            k1 = k1s[start:start + 5000, None]
            k2 = k2s[start:start + 5000, None]
            t = times[None, :]
            pred = (k1 * 100.0 / (k2 - k1)) * (np.exp(-k1 * t) - np.exp(-k2 * t))
            mse = np.mean((pred - observations[None, :]) ** 2, axis=1)
            i = int(np.argmin(mse))
            if float(mse[i]) < best_mse:
                best_mse = float(mse[i])
                best_pair = (float(k1[i, 0]), float(k2[i, 0]))
        winners.append((best_pair[0], best_pair[1], best_mse))
    return winners


def assert_mc_result(times, observations, require_three_decimals=True):
    raw = (HOME / 'best_params.json').read_text()
    params = json.loads(raw)
    assert set(params) >= {'k1', 'k2'}
    k1, k2 = float(params['k1']), float(params['k2'])
    assert np.isfinite(k1) and np.isfinite(k2)
    assert 0.1 <= k1 <= 1.0 and 0.1 <= k2 <= 1.0

    if require_three_decimals:
        assert re.search(r'"k1"\s*:\s*-?\d+\.\d{3}(?=\s*[,}])', raw), 'k1 is not stored to 3 decimal places'
        assert re.search(r'"k2"\s*:\s*-?\d+\.\d{3}(?=\s*[,}])', raw), 'k2 is not stored to 3 decimal places'

    winners = monte_carlo_candidates(times, observations)
    assert any(abs(k1 - wk1) <= 0.003 and abs(k2 - wk2) <= 0.003
               for wk1, wk2, _ in winners), (
        f'({k1}, {k2}) is not the seeded 100,000-pair Monte Carlo optimum; candidates={winners}'
    )

    submitted_mse = float(np.mean((b_exact(times, k1, k2) - observations) ** 2))
    assert submitted_mse <= min(w[2] for w in winners) + 0.02

    curve_times, b_num = load_curve()
    assert len(curve_times) == len(times)
    assert np.allclose(curve_times, times, rtol=0, atol=1e-10)
    assert np.max(np.abs(b_num - b_exact(curve_times, k1, k2))) < 0.05


def expected_clean_rows():
    expected = [['time', 'B_conc']]
    with open(HOME / 'raw_obs.txt') as f:
        header = [part.strip() for part in next(f).split('|')]
        subject_i = header.index('subject_id')
        time_i = header.index('time_hours')
        b_i = header.index('B_concentration')
        for line in f:
            fields = [part.strip() for part in line.rstrip('\n').split('|')]
            if fields[subject_i] == '42':
                expected.append([fields[time_i], fields[b_i]])
    return expected


def test_00_artifacts_execute_and_behave():
    mc_path = HOME / 'mc_fit.py'
    r_path = HOME / 'validate.R'
    assert mc_path.is_file() and not mc_path.is_symlink(), 'mc_fit.py must be a regular file'
    assert r_path.is_file() and not r_path.is_symlink(), 'validate.R must be a regular file'

    source = mc_path.read_text()
    assert re.search(r'\bseed\s*\(\s*42\s*\)', source), 'mc_fit.py must set the NumPy seed to 42'
    assert re.search(r'\b100000\b', source), 'mc_fit.py must generate exactly 100,000 parameter pairs'

    clean_path = HOME / 'clean_obs.csv'
    reference_path = HOME / 'reference.json'
    original_clean = clean_path.read_bytes()
    original_reference = reference_path.read_bytes()

    synthetic_times = np.arange(0.0, 11.0)
    synthetic_obs = b_exact(synthetic_times, 0.62, 0.28)
    try:
        with open(clean_path, 'w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['time', 'B_conc'])
            writer.writerows(zip(synthetic_times, synthetic_obs))
        subprocess.run(['python3', str(mc_path)], cwd=HOME, check=True, timeout=600)
        assert_mc_result(synthetic_times, synthetic_obs)
    finally:
        clean_path.write_bytes(original_clean)
        reference_path.write_bytes(original_reference)

    # Execute the fitter on the actual extracted observations and independently
    # verify its seeded Monte Carlo result.
    subprocess.run(['python3', str(mc_path)], cwd=HOME, check=True, timeout=600)
    with open(clean_path, newline='') as f:
        rows = list(csv.reader(f))[1:]
    times = np.asarray([float(r[0]) for r in rows])
    observations = np.asarray([float(r[1]) for r in rows])
    assert_mc_result(times, observations)

    # Exercise validate.R on deliberately invalid data and a changed threshold,
    # proving that it reads the curve, parameters, and reference file.
    curve_path = HOME / 'best_fit_curve.csv'
    canonical_curve = curve_path.read_bytes()
    try:
        curve_times, b_num = load_curve()
        with open(curve_path, 'w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['time', 'B_num'])
            writer.writerows(zip(curve_times, b_num + 1.0))
        reference_path.write_text('{"k2_threshold": 2.0}\n')
        subprocess.run(['Rscript', str(r_path)], cwd=HOME, check=True, timeout=120)
        lines = [x.strip() for x in (HOME / 'validation_result.txt').read_text().splitlines() if x.strip()]
        assert lines == ['INVALID', 'SLOW']
    finally:
        curve_path.write_bytes(canonical_curve)
        reference_path.write_bytes(original_reference)

    subprocess.run(['Rscript', str(r_path)], cwd=HOME, check=True, timeout=120)


def test_clean_obs_csv():
    """Test that clean_obs.csv is correctly extracted for subject 42."""
    file_path = "/home/user/clean_obs.csv"
    assert os.path.exists(file_path), f"File missing: {file_path}"

    with open(file_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "clean_obs.csv is empty."
    assert rows[0] == ["time", "B_conc"], f"Incorrect header in clean_obs.csv: {rows[0]}"
    assert len(rows) == 12, f"Expected 1 header + 11 data rows, got {len(rows)} total rows."
    assert float(rows[1][0]) == 0.0, "First time point should be 0."

    expected = expected_clean_rows()
    assert len(rows) == len(expected)
    for actual, wanted in zip(rows[1:], expected[1:]):
        assert len(actual) == 2
        assert float(actual[0]) == float(wanted[0])
        assert float(actual[1]) == float(wanted[1])


def test_best_params_json():
    """Test that best_params.json contains valid k1 and k2."""
    file_path = "/home/user/best_params.json"
    assert os.path.exists(file_path), f"File missing: {file_path}"

    with open(file_path, "r") as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("best_params.json is not valid JSON.")

    assert "k1" in params, "Missing 'k1' in best_params.json"
    assert "k2" in params, "Missing 'k2' in best_params.json"
    k1 = float(params["k1"])
    k2 = float(params["k2"])
    assert 0.34 < k1 < 0.37, f"k1 value {k1} is outside the expected range (0.34 - 0.37)"
    assert 0.73 < k2 < 0.78, f"k2 value {k2} is outside the expected range (0.73 - 0.78)"


def test_best_fit_curve_csv():
    """Test that best_fit_curve.csv exists and has correct headers."""
    file_path = "/home/user/best_fit_curve.csv"
    assert os.path.exists(file_path), f"File missing: {file_path}"

    with open(file_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "best_fit_curve.csv is empty."
    assert rows[0] == ["time", "B_num"], f"Incorrect header in best_fit_curve.csv: {rows[0]}"
    assert len(rows) == 12, f"Expected 1 header + 11 data rows, got {len(rows)} total rows."

    params = load_params()
    values = np.asarray([[float(x), float(y)] for x, y in rows[1:]])
    assert np.all(np.isfinite(values))
    expected_times = np.arange(0.0, 11.0)
    assert np.allclose(values[:, 0], expected_times, rtol=0, atol=1e-10)
    analytical = b_exact(values[:, 0], float(params['k1']), float(params['k2']))
    assert np.max(np.abs(values[:, 1] - analytical)) < 0.05


def test_validation_result_txt():
    """Test that validation_result.txt contains the correct output."""
    file_path = "/home/user/validation_result.txt"
    assert os.path.exists(file_path), f"File missing: {file_path}"

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in validation_result.txt, got {len(lines)}"
    assert lines[0] == "VALID", f"Expected first line to be 'VALID', got '{lines[0]}'"
    assert lines[1] == "FAST", f"Expected second line to be 'FAST', got '{lines[1]}'"

    params = load_params()
    threshold = json.loads((HOME / 'reference.json').read_text())['k2_threshold']
    times, b_num = load_curve()
    max_difference = float(np.max(np.abs(b_num - b_exact(times, float(params['k1']), float(params['k2'])))))
    assert (lines[0] == 'VALID') == (max_difference < 0.05)
    assert (lines[1] == 'FAST') == (float(params['k2']) > float(threshold))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
