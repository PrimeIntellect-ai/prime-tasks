#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import sys
from pathlib import Path

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
from scipy.optimize import curve_fit

DATA_PATH = Path('/home/user/data/melting_curve.csv')
JSON_PATH = Path('/home/user/results/tm_posterior.json')
PLOT_PATH = Path('/home/user/results/fit_plot.png')


def read_results():
    assert JSON_PATH.is_file(), f'JSON results file {JSON_PATH} does not exist.'
    try:
        with JSON_PATH.open() as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {JSON_PATH} is not valid JSON: {exc}')

    required_keys = ['tm_mean', 'tm_2_5', 'tm_97_5']
    assert set(data) == set(required_keys), f'{JSON_PATH} must contain exactly {required_keys}.'
    for key in required_keys:
        assert isinstance(data[key], (int, float)), f"Value for '{key}' must be a number."
        assert math.isfinite(float(data[key])), f"Value for '{key}' must be finite."
    return {key: float(data[key]) for key in required_keys}


def check_plot():
    assert PLOT_PATH.is_file(), f'Plot file {PLOT_PATH} does not exist.'
    with PLOT_PATH.open('rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f'File {PLOT_PATH} is not a valid PNG image.'
    try:
        image = mpimg.imread(PLOT_PATH)
    except Exception as exc:
        raise AssertionError(f'Plot cannot be decoded as a PNG: {exc}')
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, 'Plot is unreasonably small.'
    assert float(np.nanstd(image)) > 0.01, 'Plot image has no meaningful graphical content.'


def logistic(t, lower, upper, steepness, tm):
    z = np.clip(-steepness * (t - tm), -700, 700)
    return lower + (upper - lower) / (1.0 + np.exp(z))


def script_candidates():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '.local', '__pycache__', '.git'}]
        for name in files:
            if name.endswith('.py'):
                candidates.append(Path(root) / name)
    assert candidates, 'No Python analysis script was written under /home/user.'
    return sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True)


def test_outputs_and_executed_analysis():
    # Preserve all assertions made by the original verifier on the submitted outputs.
    check_plot()
    original = read_results()
    tm_mean = original['tm_mean']
    tm_low = original['tm_2_5']
    tm_high = original['tm_97_5']
    assert 68.0 <= tm_mean <= 69.0, f'tm_mean ({tm_mean}) is out of expected bounds (68.0 - 69.0).'
    assert 67.0 <= tm_low <= 68.5, f'tm_2_5 ({tm_low}) is out of expected bounds (67.0 - 68.5).'
    assert 68.5 <= tm_high <= 70.0, f'tm_97_5 ({tm_high}) is out of expected bounds (68.5 - 70.0).'
    assert tm_low < tm_mean < tm_high, f'Credible intervals are invalid: {tm_low} < {tm_mean} < {tm_high} is False.'

    original_data = DATA_PATH.read_bytes()
    original_json = JSON_PATH.read_bytes()
    original_plot = PLOT_PATH.read_bytes()

    # Use a verification-time melting curve whose Tm is not fixed in the test.
    seed = int.from_bytes(os.urandom(8), 'little')
    rng = np.random.default_rng(seed)
    true_tm = float(rng.choice([rng.uniform(57.0, 63.0), rng.uniform(75.0, 81.0)]))
    temperatures = np.linspace(40.0, 90.0, 61)
    fluorescence = logistic(temperatures, 7.5, 104.0, 0.43, true_tm)
    fluorescence += rng.normal(0.0, 1.8, temperatures.size)
    synthetic = pd.DataFrame({'Temperature': temperatures, 'Fluorescence': fluorescence})

    popt, pcov = curve_fit(
        logistic,
        temperatures,
        fluorescence,
        p0=[float(fluorescence.min()), float(fluorescence.max()), 0.4, true_tm],
        bounds=([-100.0, 0.0, 0.01, 40.0], [100.0, 250.0, 5.0, 90.0]),
        maxfev=50000,
    )
    expected_tm = float(popt[3])
    expected_se = float(math.sqrt(max(pcov[3, 3], 1e-12)))

    failures = []
    success = False
    try:
        for candidate in script_candidates():
            synthetic.to_csv(DATA_PATH, index=False)
            JSON_PATH.unlink(missing_ok=True)
            PLOT_PATH.unlink(missing_ok=True)
            try:
                proc = subprocess.run(
                    [sys.executable, str(candidate)],
                    cwd='/home/user',
                    env={**os.environ, 'MPLBACKEND': 'Agg'},
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=240,
                )
                if proc.returncode != 0:
                    failures.append(f'{candidate}: exited {proc.returncode}: {proc.stdout[-500:]}')
                    continue
                values = read_results()
                check_plot()
                low, mean, high = values['tm_2_5'], values['tm_mean'], values['tm_97_5']
                assert low < mean < high
                tolerance = max(0.75, 3.0 * expected_se)
                assert abs(mean - expected_tm) <= tolerance, (
                    f'{candidate} did not recompute Tm from the changed data: got {mean}, expected about {expected_tm}'
                )
                assert low - 0.4 <= expected_tm <= high + 0.4, 'Credible interval is inconsistent with the independently fitted Tm.'
                width = high - low
                expected_width = max(3.92 * expected_se, 0.05)
                assert 0.10 <= width <= 5.0, f'Posterior interval width {width} is implausible.'
                assert 0.2 * expected_width <= width <= 5.0 * expected_width, (
                    f'Posterior interval width {width} is inconsistent with the data uncertainty.'
                )
                success = True
                break
            except Exception as exc:
                failures.append(f'{candidate}: {exc}')
        assert success, 'No submitted Python script successfully recomputed the posterior and plot on changed data. ' + ' | '.join(failures[-5:])
    finally:
        DATA_PATH.write_bytes(original_data)
        JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
        JSON_PATH.write_bytes(original_json)
        PLOT_PATH.write_bytes(original_plot)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
