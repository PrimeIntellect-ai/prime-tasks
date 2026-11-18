#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import json
import math
import os
import stat
import subprocess
import sys

import numpy as np
import pandas as pd
from PIL import Image

SCRIPT_PATH = '/home/user/analyze.py'
DATA_PATH = '/home/user/sensor_data.csv'
REPORT_PATH = '/home/user/report.json'
PLOT_PATH = '/home/user/vibration_hist.png'


def check_script():
    assert os.path.exists(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f'{SCRIPT_PATH} is not a regular file'
    assert os.path.getsize(SCRIPT_PATH) > 0, f'{SCRIPT_PATH} is empty'
    with open(SCRIPT_PATH, 'rb') as f:
        source = f.read()
    compile(source, SCRIPT_PATH, 'exec')


def run_script():
    for path in (REPORT_PATH, PLOT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'analyze.py exited with status {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def load_report():
    # Preserve the original existence and valid-JSON assertions.
    assert os.path.isfile(REPORT_PATH), f'Report file not found at {REPORT_PATH}'
    try:
        with open(REPORT_PATH, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'The file {REPORT_PATH} is not valid JSON: {exc}')


def check_original_report(data):
    # Preserve all original report-content assertions.
    assert 'cleaned_rows' in data, "Key 'cleaned_rows' missing from report.json"
    assert data['cleaned_rows'] == 8, f"Expected 8 cleaned rows, got {data['cleaned_rows']}"

    assert 't_stat' in data, "Key 't_stat' missing from report.json"
    t_stat = data['t_stat']
    assert isinstance(t_stat, (int, float)), 't_stat must be a number'
    assert -0.101 <= t_stat <= -0.099, (
        f't_stat {t_stat} is not within the expected range (-0.101 to -0.099)'
    )

    assert 'ci_lower' in data, "Key 'ci_lower' missing from report.json"
    ci_lower = data['ci_lower']
    assert isinstance(ci_lower, (int, float)), 'ci_lower must be a number'
    assert 4.69 <= ci_lower <= 4.70, (
        f'ci_lower {ci_lower} is not within the expected range (4.69 to 4.70)'
    )

    assert 'ci_upper' in data, "Key 'ci_upper' missing from report.json"
    ci_upper = data['ci_upper']
    assert isinstance(ci_upper, (int, float)), 'ci_upper must be a number'
    assert 5.27 <= ci_upper <= 5.29, (
        f'ci_upper {ci_upper} is not within the expected range (5.27 to 5.29)'
    )


def check_plot():
    # Preserve the original plot existence/nonempty assertions, then verify it is
    # a real, nonblank PNG image.
    assert os.path.isfile(PLOT_PATH), f'Plot file not found at {PLOT_PATH}'
    assert os.path.getsize(PLOT_PATH) > 0, f'Plot file {PLOT_PATH} is empty (0 bytes).'
    with Image.open(PLOT_PATH) as image:
        assert image.format == 'PNG', f'{PLOT_PATH} is not a valid PNG image'
        image.verify()
    with Image.open(PLOT_PATH) as image:
        assert image.width > 1 and image.height > 1, 'Plot has invalid dimensions'
        extrema = image.convert('RGB').getextrema()
        assert any(low != high for low, high in extrema), 'Plot image is blank/uniform'
    with open(PLOT_PATH, 'rb') as f:
        return f.read()


def derive_expected(csv_path):
    raw = pd.read_csv(csv_path)
    required = ['temperature', 'pressure', 'vibration']
    assert all(column in raw.columns for column in required)

    converted = raw.copy()
    invalid = np.zeros(len(raw), dtype=bool)
    for column in required:
        numeric = pd.to_numeric(raw[column], errors='coerce')
        # Existing NaN values are allowed at this stage; non-null values that
        # become NaN are the rows that cannot be cast to float.
        invalid |= (numeric.isna() & raw[column].notna()).to_numpy()
        converted[column] = numeric.astype(float)

    cleaned = converted.loc[~invalid].copy()
    for column in ('temperature', 'pressure'):
        cleaned[column] = cleaned[column].fillna(cleaned[column].median())

    matrix = cleaned[['temperature', 'pressure']].to_numpy(dtype=float)
    median_vector = np.median(matrix, axis=0)
    distances = np.linalg.norm(matrix - median_vector, axis=1)
    cleaned = cleaned.loc[distances <= 20.0]

    vibration = cleaned['vibration'].to_numpy(dtype=float)
    n = len(vibration)
    mean = float(np.mean(vibration))
    sample_std = float(np.std(vibration, ddof=1))
    standard_error = sample_std / math.sqrt(n)
    t_stat = (mean - 5.0) / standard_error

    # 97.5th-percentile Student-t values for the sample sizes exercised here.
    t_critical = {
        7: 2.3646242516,
        8: 2.3060041352,
    }[n - 1]
    return {
        't_stat': round(t_stat, 4),
        'ci_lower': round(mean - t_critical * standard_error, 4),
        'ci_upper': round(mean + t_critical * standard_error, 4),
        'cleaned_rows': n,
    }


def check_dynamic_report(actual, expected):
    for key in ('t_stat', 'ci_lower', 'ci_upper', 'cleaned_rows'):
        assert key in actual, f"Key '{key}' missing from report.json"
        assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool), (
            f'{key} must be numeric'
        )
        assert math.isfinite(float(actual[key])), f'{key} must be finite'
        assert actual[key] == expected[key], (
            f'{key}: expected {expected[key]}, got {actual[key]}'
        )


def main():
    check_script()
    with open(DATA_PATH, 'rb') as f:
        original_csv = f.read()

    try:
        # Execute the submitted artifact rather than trusting pre-created files.
        run_script()
        original_report = load_report()
        check_original_report(original_report)
        original_plot = check_plot()

        # Exercise the same pipeline on unseen values. This dataset includes
        # uncastable values, missing values, an outlier, and a point exactly at
        # distance 20.0, which must be retained.
        alternate = pd.DataFrame({
            'temperature': [10.0, 12.0, np.nan, 11.0, 60.0, 'ERROR', 9.0, 30.0, 32.0, 10.0, 8.0, 13.0],
            'pressure': [100.0, 102.0, 101.0, np.nan, 160.0, 100.0, 99.0, 100.0, 100.0, 98.0, 103.0, 97.0],
            'vibration': [6.0, 7.0, 8.0, 9.0, 100.0, 5.0, 4.0, 10.0, 12.0, 'BAD', 3.0, 11.0],
        })
        alternate.to_csv(DATA_PATH, index=False)
        expected = derive_expected(DATA_PATH)

        run_script()
        dynamic_report = load_report()
        check_dynamic_report(dynamic_report, expected)
        dynamic_plot = check_plot()
        assert dynamic_plot != original_plot, 'Plot did not change when vibration data changed'
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_csv)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
