#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_spectroscopy.py
import ast
import json
import math
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.optimize import curve_fit

DATA_PATH = Path('/home/user/spectroscopy_data.csv')
RESULTS_PATH = Path('/home/user/spectroscopy_results.json')
HOME = Path('/home/user')


def model_1peak(x, a1, x1, w1, m, c):
    return a1 / (1 + ((x - x1) / w1) ** 2) + m * x + c


def model_2peak(x, a1, x1, w1, a2, x2, w2, m, c):
    return (a1 / (1 + ((x - x1) / w1) ** 2)
            + a2 / (1 + ((x - x2) / w2) ** 2) + m * x + c)


def calculate_expected(data_path):
    df = pd.read_csv(data_path)
    assert list(df.columns) == ['wavelength', 'intensity']
    x = df['wavelength'].to_numpy(dtype=float)
    y = df['intensity'].to_numpy(dtype=float)
    n = len(x)

    p1, _ = curve_fit(model_1peak, x, y, p0=[10, 50, 5, 0, 0])
    p2, _ = curve_fit(model_2peak, x, y, p0=[10, 40, 5, 10, 60, 5, 0, 0])

    rss1 = float(np.sum((y - model_1peak(x, *p1)) ** 2))
    rss2 = float(np.sum((y - model_2peak(x, *p2)) ** 2))
    bic1 = n * np.log(rss1 / n) + 5 * np.log(n)
    bic2 = n * np.log(rss2 / n) + 8 * np.log(n)

    use_two = bic2 < bic1
    model = model_2peak if use_two else model_1peak
    p0 = [10, 40, 5, 10, 60, 5, 0, 0] if use_two else [10, 50, 5, 0, 0]

    centers1 = []
    centers2 = []
    np.random.seed(42)
    for _ in range(500):
        indices = np.random.choice(n, size=n, replace=True)
        try:
            fitted, _ = curve_fit(model, x[indices], y[indices], p0=p0)
        except RuntimeError:
            continue
        centers1.append(float(fitted[1]))
        if use_two:
            centers2.append(float(fitted[4]))

    assert centers1, 'Reference bootstrap produced no successful fits'
    expected = {
        'bic_1peak': round(float(bic1), 2),
        'bic_2peak': round(float(bic2), 2),
        'best_model': '2-peak' if use_two else '1-peak',
        'bootstrap_ci_x1': [round(float(v), 2) for v in np.percentile(centers1, [2.5, 97.5])],
    }
    if use_two:
        assert centers2, 'Reference bootstrap produced no successful second-peak fits'
        expected['bootstrap_ci_x2'] = [round(float(v), 2) for v in np.percentile(centers2, [2.5, 97.5])]
    return expected


def load_results():
    assert RESULTS_PATH.is_file(), f'Missing required file: {RESULTS_PATH}'
    try:
        with RESULTS_PATH.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {RESULTS_PATH} is not valid JSON') from exc


def assert_number(value, name):
    assert isinstance(value, (int, float)), f'{name} must be a number'
    assert math.isfinite(float(value)), f'{name} must be finite'


def assert_results(results, expected, bic_tolerance, ci_tolerance):
    required = {'bic_1peak', 'bic_2peak', 'best_model', 'bootstrap_ci_x1'}
    if expected['best_model'] == '2-peak':
        required.add('bootstrap_ci_x2')
    for key in required:
        assert key in results, f"Missing key '{key}' in {RESULTS_PATH}"

    assert results['best_model'] == expected['best_model'], 'Incorrect best_model'
    assert_number(results['bic_1peak'], 'bic_1peak')
    assert_number(results['bic_2peak'], 'bic_2peak')
    if expected['best_model'] == '2-peak':
        assert results['best_model'] == '2-peak'
        assert results['bic_2peak'] < results['bic_1peak'], 'Expected bic_2peak to be less than bic_1peak'
    else:
        assert results['bic_1peak'] < results['bic_2peak'], 'Expected bic_1peak to be less than bic_2peak'

    assert math.isclose(float(results['bic_1peak']), expected['bic_1peak'], abs_tol=bic_tolerance)
    assert math.isclose(float(results['bic_2peak']), expected['bic_2peak'], abs_tol=bic_tolerance)

    for key in ('bootstrap_ci_x1', 'bootstrap_ci_x2'):
        if key not in expected:
            assert key not in results, f'{key} must be omitted for a 1-peak result'
            continue
        ci = results[key]
        assert isinstance(ci, list) and len(ci) == 2, f'{key} must be a list of 2 numbers'
        assert_number(ci[0], key + '[0]')
        assert_number(ci[1], key + '[1]')
        assert ci[0] < ci[1], f'{key} lower bound must be less than upper bound'
        assert math.isclose(float(ci[0]), expected[key][0], abs_tol=ci_tolerance)
        assert math.isclose(float(ci[1]), expected[key][1], abs_tol=ci_tolerance)


def run_script(script):
    if RESULTS_PATH.exists():
        RESULTS_PATH.unlink()
    completed = subprocess.run(
        [sys.executable, str(script)], cwd=str(HOME),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=240,
    )
    if completed.returncode != 0:
        raise AssertionError(f'{script} exited with status {completed.returncode}: {completed.stderr[-1000:]}')
    return load_results()


def make_challenge(path):
    rng = np.random.RandomState(7319)
    x = np.linspace(3.0, 97.0, 137)
    y = (14.2 / (1 + ((x - 35.0) / 3.7) ** 2)
         + 7.8 / (1 + ((x - 66.0) / 6.2) ** 2)
         - 0.013 * x + 2.4)
    y += rng.normal(0, 0.35, size=x.size)
    pd.DataFrame({'wavelength': x, 'intensity': y}).to_csv(path, index=False)


def main():
    assert DATA_PATH.is_file(), f'Missing input data: {DATA_PATH}'
    original_data = DATA_PATH.read_bytes()
    original_expected = calculate_expected(DATA_PATH)
    assert original_expected['best_model'] == '2-peak'

    scripts = []
    for path in HOME.rglob('*.py'):
        if path.is_file() and not path.is_symlink():
            try:
                ast.parse(path.read_text())
            except (OSError, UnicodeDecodeError, SyntaxError):
                continue
            scripts.append(path)
    assert scripts, 'No executable Python analysis script was created under /home/user'

    selected = None
    original_result_bytes = None
    errors = []
    for script in sorted(scripts):
        DATA_PATH.write_bytes(original_data)
        try:
            result = run_script(script)
            # Preserve all original structural, model-selection, ordering, and
            # approximate numerical checks, but derive their targets from data.
            assert_results(result, original_expected, bic_tolerance=5.0, ci_tolerance=1.0)
            selected = script
            original_result_bytes = RESULTS_PATH.read_bytes()
            break
        except Exception as exc:
            errors.append(f'{script}: {exc}')

    assert selected is not None, 'No Python script generated valid original-data results. ' + ' | '.join(errors[-3:])

    try:
        make_challenge(DATA_PATH)
        challenge_expected = calculate_expected(DATA_PATH)
        challenge_result = run_script(selected)
        assert_results(challenge_result, challenge_expected, bic_tolerance=0.25, ci_tolerance=0.40)
    finally:
        DATA_PATH.write_bytes(original_data)
        if original_result_bytes is not None:
            RESULTS_PATH.write_bytes(original_result_bytes)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_spectroscopy.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
