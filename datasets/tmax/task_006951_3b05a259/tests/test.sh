#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import subprocess
from pathlib import Path

import numpy as np
import pytest
from scipy.optimize import brentq, curve_fit

RAW_PATH = Path('/home/user/raw_signal.csv')
LABEL_PATH = Path('/home/user/labels.json')


def load_labels(path):
    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {path} is not valid JSON.')

    expected_keys = {'mu1', 'mu2', 'intersection_x'}
    actual_keys = set(data.keys())
    assert expected_keys.issubset(actual_keys), (
        f'JSON is missing required keys. Expected: {expected_keys}, Found: {actual_keys}'
    )
    assert actual_keys == expected_keys, f'JSON must contain exactly {expected_keys}, found {actual_keys}'

    for key in expected_keys:
        assert isinstance(data[key], (int, float)), f'{key} must be a number'
        assert not isinstance(data[key], bool), f'{key} must be a number'
        assert math.isfinite(data[key]), f'{key} must be finite'
    return data


def model(x, a1, mu1, sigma1, a2, mu2, sigma2):
    return (1.0
            - a1 * np.exp(-((x - mu1) ** 2) / (2.0 * sigma1 ** 2))
            - a2 * np.exp(-((x - mu2) ** 2) / (2.0 * sigma2 ** 2)))


def make_case(rng):
    mu1 = rng.uniform(455.0, 535.0)
    mu2 = rng.uniform(650.0, 745.0)
    sigma1 = rng.uniform(14.0, 27.0)
    sigma2 = rng.uniform(22.0, 39.0)
    a1 = rng.uniform(0.35, 0.70)
    a2 = rng.uniform(0.38, 0.72)

    x = np.linspace(400.0, 1000.0, 3601)
    y = model(x, a1, mu1, sigma1, a2, mu2, sigma2)
    y += np.random.default_rng(rng.randrange(1, 2**63)).normal(0.0, 0.0015, len(x))
    bad = x > 800.0
    y[bad] += (x[bad] - 800.0) ** 2 * np.sin(x[bad] * 7.37) * 0.08

    usable = ~bad
    fitted, _ = curve_fit(
        model,
        x[usable],
        y[usable],
        p0=[0.5, 500.0, 20.0, 0.55, 700.0, 30.0],
        bounds=([0.05, 420.0, 5.0, 0.05, 600.0, 5.0],
                [1.2, 590.0, 70.0, 1.2, 790.0, 70.0]),
        maxfev=50000,
    )
    fa1, fmu1, fs1, fa2, fmu2, fs2 = fitted
    assert fmu1 < fmu2

    def difference(v):
        return (fa1 * math.exp(-((v - fmu1) ** 2) / (2.0 * fs1 ** 2))
                - fa2 * math.exp(-((v - fmu2) ** 2) / (2.0 * fs2 ** 2)))

    intersection = brentq(difference, fmu1, fmu2)
    return x, y, {'mu1': fmu1, 'mu2': fmu2, 'intersection_x': intersection}


def write_signal(x, y):
    with open(RAW_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['wavelength', 'intensity'])
        writer.writerows(zip(x, y))


def script_passes(script, cases):
    for x, y, expected in cases:
        write_signal(x, y)
        if LABEL_PATH.exists():
            LABEL_PATH.unlink()
        try:
            result = subprocess.run(
                ['python3', str(script)],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=40,
            )
        except (subprocess.TimeoutExpired, OSError):
            return False
        if result.returncode != 0 or not LABEL_PATH.is_file():
            return False
        try:
            got = load_labels(LABEL_PATH)
        except (AssertionError, OSError, TypeError, ValueError):
            return False

        if not (abs(got['mu1'] - expected['mu1']) <= 0.20
                and abs(got['mu2'] - expected['mu2']) <= 0.20
                and abs(got['intersection_x'] - expected['intersection_x']) <= 0.35
                and got['mu1'] < got['intersection_x'] < got['mu2']):
            return False
    return True


def test_labels_json_exists_and_valid():
    file_path = '/home/user/labels.json'
    assert os.path.isfile(file_path), f'Required output file is missing: {file_path}'
    data = load_labels(file_path)

    mu1 = data['mu1']
    mu2 = data['mu2']
    intersection_x = data['intersection_x']

    # Preserve the original checks on the submitted output.
    assert abs(mu1 - 500.0) < 1.0, f'mu1 is out of expected range. Expected ~500.0, got {mu1}'
    assert abs(mu2 - 700.0) < 1.0, f'mu2 is out of expected range. Expected ~700.0, got {mu2}'
    assert abs(intersection_x - 585.9) < 2.0, (
        f'intersection_x is out of expected range. Expected ~585.9, got {intersection_x}'
    )

    raw_backup = RAW_PATH.read_bytes()
    labels_backup = LABEL_PATH.read_bytes()
    try:
        scripts = sorted(
            p for p in Path('/home/user').rglob('*.py')
            if p.is_file() and '__pycache__' not in p.parts
        )
        assert scripts, 'No Python script was created under /home/user'

        rng = secrets.SystemRandom()
        cases = [make_case(rng), make_case(rng)]
        assert any(script_passes(script, cases) for script in scripts), (
            'No submitted Python script successfully processed independently generated '
            'signals, ignored the wavelength > 800 artifact, and produced fitted labels.'
        )
    finally:
        RAW_PATH.write_bytes(raw_backup)
        LABEL_PATH.write_bytes(labels_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
