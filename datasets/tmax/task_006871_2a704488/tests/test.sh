#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import shutil
import stat
import subprocess
import tempfile

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest
from scipy.signal import savgol_filter
from scipy.stats import ttest_ind

CONTROL_DIR = '/home/user/data/control'
TREATMENT_DIR = '/home/user/data/treatment'
SCRIPT_PATH = '/home/user/analyze.py'
STATS_PATH = '/home/user/stats.json'
PLOT_PATH = '/home/user/mean_spectra.png'


def process_spectrum(wavenumber, intensity):
    smoothed = savgol_filter(intensity, window_length=21, polyorder=3)
    baseline = np.linspace(smoothed[0], smoothed[-1], len(smoothed))
    return smoothed - baseline


def compute_expected():
    features = {'control': {500: [], 1000: [], 1500: []},
                'treatment': {500: [], 1000: [], 1500: []}}
    windows = {500: (480, 520), 1000: (980, 1020), 1500: (1480, 1520)}

    for group, directory in [('control', CONTROL_DIR), ('treatment', TREATMENT_DIR)]:
        files = sorted(glob.glob(os.path.join(directory, '*.csv')))
        assert files, f'No CSV files found in {directory}'
        for path in files:
            df = pd.read_csv(path)
            assert {'wavenumber', 'intensity'} <= set(df.columns)
            x = df['wavenumber'].to_numpy(dtype=float)
            y = process_spectrum(x, df['intensity'].to_numpy(dtype=float))
            for peak, (low, high) in windows.items():
                mask = (x >= low) & (x <= high)
                assert mask.any()
                features[group][peak].append(float(np.max(y[mask])))

    return {
        str(peak): float(ttest_ind(features['control'][peak],
                                  features['treatment'][peak]).pvalue)
        for peak in (500, 1000, 1500)
    }


@pytest.fixture(scope='session', autouse=True)
def execute_submission_on_fresh_inputs():
    assert os.path.exists(SCRIPT_PATH), f'Expected script missing: {SCRIPT_PATH}'
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode) and not os.path.islink(SCRIPT_PATH), \
        f'{SCRIPT_PATH} must be a regular Python file'
    assert os.path.getsize(SCRIPT_PATH) > 0, f'{SCRIPT_PATH} is empty'

    backup_root = tempfile.mkdtemp(prefix='raman_backup_')
    try:
        for group, directory in [('control', CONTROL_DIR), ('treatment', TREATMENT_DIR)]:
            backup_dir = os.path.join(backup_root, group)
            os.makedirs(backup_dir)
            for path in glob.glob(os.path.join(directory, '*.csv')):
                shutil.copy2(path, os.path.join(backup_dir, os.path.basename(path)))
                os.remove(path)

        # Use a fresh valid cohort so hard-coded p-values cannot pass. Paired base
        # spectra make the unchanged peaks reliably non-significant, while only
        # treatment has the additional 1000 cm^-1 peak.
        x = np.linspace(400, 2000, 1601)
        rng = np.random.default_rng(8675309)
        for i in range(10):
            noise = rng.normal(0, 0.7, x.size)
            baseline = (0.0025 + rng.normal(0, 0.0002)) * x
            p500 = (8.0 + rng.normal(0, 0.8)) * np.exp(-((x - 500) / 10) ** 2)
            p1000 = (9.0 + rng.normal(0, 0.9)) * np.exp(-((x - 1000) / 10) ** 2)
            p1500 = (7.5 + rng.normal(0, 0.8)) * np.exp(-((x - 1500) / 10) ** 2)
            control = baseline + noise + p500 + p1000 + p1500
            extra = (9.0 + rng.normal(0, 0.4)) * np.exp(-((x - 1000) / 10) ** 2)
            treatment = control + extra
            pd.DataFrame({'wavenumber': x, 'intensity': control}).to_csv(
                os.path.join(CONTROL_DIR, f'sample_{i}.csv'), index=False)
            pd.DataFrame({'wavenumber': x, 'intensity': treatment}).to_csv(
                os.path.join(TREATMENT_DIR, f'sample_{i}.csv'), index=False)

        expected = compute_expected()
        for output in (STATS_PATH, PLOT_PATH):
            if os.path.lexists(output):
                if os.path.isdir(output) and not os.path.islink(output):
                    shutil.rmtree(output)
                else:
                    os.remove(output)

        result = subprocess.run(
            ['python3', SCRIPT_PATH], cwd='/home/user',
            env={**os.environ, 'MPLBACKEND': 'Agg'},
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=180
        )
        assert result.returncode == 0, \
            f'analyze.py failed with exit code {result.returncode}:\n{result.stdout[-4000:]}'
        yield expected
    finally:
        for group, directory in [('control', CONTROL_DIR), ('treatment', TREATMENT_DIR)]:
            for path in glob.glob(os.path.join(directory, '*.csv')):
                os.remove(path)
            backup_dir = os.path.join(backup_root, group)
            if os.path.isdir(backup_dir):
                for path in glob.glob(os.path.join(backup_dir, '*.csv')):
                    shutil.copy2(path, os.path.join(directory, os.path.basename(path)))
        shutil.rmtree(backup_root, ignore_errors=True)


def test_stats_json_exists_and_valid():
    stats_path = '/home/user/stats.json'
    assert os.path.isfile(stats_path), f"Expected JSON file missing: {stats_path}"

    with open(stats_path, 'r') as f:
        try:
            stats = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {stats_path} is not valid JSON.")

    expected_keys = {"500", "1000", "1500"}
    assert set(stats.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, got {set(stats.keys())}"

    for key in expected_keys:
        val = stats[key]
        assert isinstance(val, float) or isinstance(val, int), f"Value for key '{key}' must be a number, got {type(val)}"


def test_values_match_independent_recomputation(execute_submission_on_fresh_inputs):
    expected = execute_submission_on_fresh_inputs
    with open(STATS_PATH, 'r') as f:
        actual = json.load(f)
    for key, wanted in expected.items():
        got = float(actual[key])
        assert math.isfinite(got) and 0.0 <= got <= 1.0
        assert math.isclose(got, wanted, rel_tol=1e-7, abs_tol=1e-15), \
            f'Incorrect p-value for {key}: expected {wanted}, got {got}'


def test_statistical_results():
    stats_path = '/home/user/stats.json'
    if not os.path.isfile(stats_path):
        pytest.skip("stats.json not found")

    with open(stats_path, 'r') as f:
        stats = json.load(f)

    # The treatment group has a significantly higher peak at 1000,
    # while peaks at 500 and 1500 remain the same as the control group.
    # Therefore, p-value for 1000 should be extremely small, and others should be > 0.05.
    p_500 = float(stats.get("500", 0))
    p_1000 = float(stats.get("1000", 1))
    p_1500 = float(stats.get("1500", 0))

    assert p_1000 < 1e-3, f"Expected highly significant p-value (< 1e-3) for peak 1000, got {p_1000}"
    assert p_500 > 0.01, f"Expected non-significant p-value (> 0.01) for peak 500, got {p_500}"
    assert p_1500 > 0.01, f"Expected non-significant p-value (> 0.01) for peak 1500, got {p_1500}"


def test_mean_spectra_plot_exists():
    plot_path = '/home/user/mean_spectra.png'
    assert os.path.isfile(plot_path), f"Expected plot file missing: {plot_path}"
    assert os.path.getsize(plot_path) > 0, f"Plot file {plot_path} is empty."


def test_mean_spectra_is_valid_nonblank_png():
    with open(PLOT_PATH, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'mean_spectra.png is not a PNG file'
    try:
        image = mpimg.imread(PLOT_PATH)
    except Exception as exc:
        pytest.fail(f'mean_spectra.png cannot be decoded: {exc}')
    assert image.ndim in (2, 3)
    assert image.shape[0] >= 200 and image.shape[1] >= 200, \
        f'Plot resolution is implausibly small: {image.shape}'
    assert np.isfinite(image).all(), 'Plot contains invalid pixel values'
    rgb = image[..., :3] if image.ndim == 3 else image
    assert float(np.std(rgb)) > 0.01, 'Plot appears blank or constant'
    sampled = rgb[::5, ::5]
    colors = np.unique(np.round(sampled.reshape(-1, sampled.shape[-1] if sampled.ndim == 3 else 1), 3), axis=0)
    assert len(colors) > 16, 'Plot lacks the visual content expected from two spectra'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
