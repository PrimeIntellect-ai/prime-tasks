#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

import matplotlib.image as mpimg
import numpy as np

SENSOR_PATH = Path('/home/user/sensor_data.csv')
REF_PATH = Path('/home/user/ref_derivative.csv')
REPORT_PATH = Path('/home/user/report.txt')
PLOT_PATH = Path('/home/user/plot.png')


def find_scripts():
    scripts = []
    excluded = {Path(__file__).resolve()}
    for root in (Path('/home/user'), Path('/tmp')):
        if not root.exists():
            continue
        for path in root.rglob('*'):
            try:
                if not path.is_file() or path.resolve() in excluded:
                    continue
                is_python = path.suffix.lower() == '.py'
                if not is_python:
                    with path.open('rb') as f:
                        first_line = f.readline(256)
                    is_python = first_line.startswith(b'#!') and b'python' in first_line.lower()
                if is_python:
                    scripts.append(path)
            except (OSError, UnicodeError):
                continue
    return sorted(set(scripts), key=lambda p: (p.is_relative_to('/tmp'), str(p)))


def run_script(script):
    for output in (REPORT_PATH, PLOT_PATH):
        if output.exists() or output.is_symlink():
            output.unlink()
    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    subprocess.run(
        ['python3', str(script)],
        cwd=str(script.parent),
        env=env,
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def expected_metrics(sensor, reference):
    derivative = np.gradient(sensor)
    mse = np.mean((derivative - reference) ** 2)
    noise = 1e-5 * ((-1.0) ** np.arange(sensor.size))
    noisy_derivative = np.gradient(sensor + noise)
    maxdiff = np.max(np.abs(noisy_derivative - derivative))
    integral = np.trapz(derivative)
    return float(mse), float(maxdiff), float(integral)


def check_plot():
    assert PLOT_PATH.exists(), f'Missing required file: {PLOT_PATH}'
    assert PLOT_PATH.is_file(), f'Expected a file, but found a directory: {PLOT_PATH}'
    assert PLOT_PATH.stat().st_size > 0, f'Plot file is empty: {PLOT_PATH}'
    assert PLOT_PATH.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n', 'plot.png is not a PNG file'
    image = mpimg.imread(PLOT_PATH)
    assert image.ndim in (2, 3) and image.shape[0] > 1 and image.shape[1] > 1, 'plot.png is not a valid image'
    assert np.ptp(np.asarray(image, dtype=float)) > 0, 'plot.png contains no visible content'


def check_report(sensor, reference):
    assert REPORT_PATH.exists(), f'Missing required file: {REPORT_PATH}'
    assert REPORT_PATH.is_file(), f'Expected a file, but found a directory: {REPORT_PATH}'
    content = REPORT_PATH.read_text()

    match = re.fullmatch(
        r'MSE: (-?\d+\.\d{6})\nMaxDiff: (-?\d+\.\d{6})\nIntegral: (-?\d+\.\d{6})\n?',
        content,
    )
    assert match is not None, 'report.txt does not have the required format with six decimal places'

    mse_val, maxdiff_val, integral_val = map(float, match.groups())
    expected_mse, expected_maxdiff, expected_integral = expected_metrics(sensor, reference)
    tolerance = 1e-5
    assert abs(mse_val - expected_mse) <= tolerance, f'MSE value {mse_val} is not within tolerance of {expected_mse}'
    assert abs(maxdiff_val - expected_maxdiff) <= tolerance, f'MaxDiff value {maxdiff_val} is not within tolerance of {expected_maxdiff}'
    assert abs(integral_val - expected_integral) <= tolerance, f'Integral value {integral_val} is not within tolerance of {expected_integral}'

    expected_text = (
        f'MSE: {expected_mse:.6f}\n'
        f'MaxDiff: {expected_maxdiff:.6f}\n'
        f'Integral: {expected_integral:.6f}\n'
    )
    assert content.rstrip('\n') == expected_text.rstrip('\n'), 'Report values are not correctly rounded to six decimal places'


def check_outputs(sensor, reference):
    check_plot()
    check_report(sensor, reference)


def test_script_and_outputs():
    original_sensor_bytes = SENSOR_PATH.read_bytes()
    original_ref_bytes = REF_PATH.read_bytes()
    original_sensor = np.loadtxt(SENSOR_PATH)
    original_ref = np.loadtxt(REF_PATH)

    selected = None
    errors = []
    for script in find_scripts():
        try:
            SENSOR_PATH.write_bytes(original_sensor_bytes)
            REF_PATH.write_bytes(original_ref_bytes)
            run_script(script)
            check_outputs(original_sensor, original_ref)
            selected = script
            break
        except Exception as exc:
            errors.append(f'{script}: {exc}')

    assert selected is not None, 'No submitted Python script generated correct outputs. ' + '; '.join(errors)

    indices = np.arange(original_sensor.size, dtype=float)
    varied_sensor = -0.73 * original_sensor + np.linspace(0.2, 2.4, original_sensor.size) + 0.00013 * np.sin(indices)
    varied_ref = 1.91 * original_ref - 0.002 * np.cos(indices)

    try:
        np.savetxt(SENSOR_PATH, varied_sensor, fmt='%.17g')
        np.savetxt(REF_PATH, varied_ref, fmt='%.17g')
        run_script(selected)
        check_outputs(np.loadtxt(SENSOR_PATH), np.loadtxt(REF_PATH))
    finally:
        SENSOR_PATH.write_bytes(original_sensor_bytes)
        REF_PATH.write_bytes(original_ref_bytes)
        run_script(selected)

    check_outputs(original_sensor, original_ref)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
