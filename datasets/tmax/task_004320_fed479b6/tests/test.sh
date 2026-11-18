#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import LinearRegression

SCRIPT_PATH = '/home/user/etl_step.py'
CSV_PATH = '/home/user/sensor_data.csv'
OUTPUT_PATH = '/home/user/etl_output.txt'


def compute_expected_features(csv_path):
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        data = {col: [] for col in reader.fieldnames}
        for row in reader:
            for col in reader.fieldnames:
                data[col].append(float(row[col]))

    target = data['Target']
    n = len(target)
    mean_t = sum(target) / n
    var_t = sum((t - mean_t) ** 2 for t in target)

    corrs = {}
    for col in ['F1', 'F2', 'F3', 'F4', 'F5']:
        x = data[col]
        mean_x = sum(x) / n
        cov = sum((x[i] - mean_x) * (target[i] - mean_t) for i in range(n))
        var_x = sum((xi - mean_x) ** 2 for xi in x)
        corr = cov / math.sqrt(var_x * var_t)
        corrs[col] = abs(corr)

    sorted_features = sorted(corrs.keys(), key=lambda k: corrs[k], reverse=True)
    return sorted(sorted_features[:2])


def compute_expected_result(csv_path):
    features = compute_expected_features(csv_path)
    df = pd.read_csv(csv_path)
    df['Interact'] = df[features[0]] * df[features[1]]

    np.random.seed(42)
    coefficients = []
    for _ in range(1000):
        sample = df.sample(n=len(df), replace=True)
        model = LinearRegression(fit_intercept=False)
        model.fit(sample[['Interact']], sample['Target'])
        coefficients.append(model.coef_[0])

    return f'{features[0]},{features[1]}', f'{np.mean(coefficients):.4f}'


def read_output():
    assert os.path.exists(OUTPUT_PATH), 'Output file missing.'
    assert os.path.isfile(OUTPUT_PATH), f'Path {OUTPUT_PATH} is not a file.'
    with open(OUTPUT_PATH, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def run_script():
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'etl_step.py exited with status {result.returncode}. stderr: {result.stderr}'
    )


def assert_exact_output(expected_line1, expected_line2):
    lines = read_output()
    assert len(lines) >= 2, 'Output file must contain at least two lines.'
    assert lines[0] == expected_line1, (
        f"Expected line 1 to be '{expected_line1}', got '{lines[0]}'."
    )
    assert re.match(r'^-?\d+\.\d{4}$', lines[1]), (
        f"Expected line 2 to be a float rounded to exactly 4 decimal places, got '{lines[1]}'."
    )
    assert lines[1] == expected_line2, (
        f"Expected bootstrap mean coefficient '{expected_line2}', got '{lines[1]}'."
    )


@pytest.fixture(scope='session', autouse=True)
def execute_and_verify_script():
    assert os.path.exists(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'Path {SCRIPT_PATH} is not a file.'
    with open(SCRIPT_PATH, 'r') as f:
        compile(f.read(), SCRIPT_PATH, 'exec')

    with open(CSV_PATH, 'rb') as f:
        original_csv = f.read()

    seed = int.from_bytes(os.urandom(16), 'big')
    rng = np.random.default_rng(seed)
    n = 173
    f1 = rng.normal(size=n)
    f2 = rng.normal(size=n)
    challenge = pd.DataFrame({
        'F1': f1,
        'F2': f2,
        'F3': rng.normal(scale=0.15, size=n),
        'F4': rng.normal(scale=0.15, size=n),
        'F5': rng.normal(scale=0.15, size=n),
        'Target': 3.7 * f1 - 2.9 * f2 + 0.83 * f1 * f2 + rng.normal(scale=0.25, size=n),
    })

    try:
        challenge.to_csv(CSV_PATH, index=False)
        expected_line1, expected_line2 = compute_expected_result(CSV_PATH)
        run_script()
        assert_exact_output(expected_line1, expected_line2)
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)

    expected_line1, expected_line2 = compute_expected_result(CSV_PATH)
    run_script()
    assert_exact_output(expected_line1, expected_line2)
    yield


def test_etl_output_exists():
    assert os.path.exists(OUTPUT_PATH), f'Output file {OUTPUT_PATH} does not exist.'
    assert os.path.isfile(OUTPUT_PATH), f'Path {OUTPUT_PATH} is not a file.'


def test_etl_output_content():
    assert os.path.exists(OUTPUT_PATH), 'Output file missing.'
    assert os.path.exists(CSV_PATH), 'Input CSV missing.'

    expected_features = compute_expected_features(CSV_PATH)
    expected_line1 = f'{expected_features[0]},{expected_features[1]}'
    _, expected_line2 = compute_expected_result(CSV_PATH)

    lines = read_output()
    assert len(lines) >= 2, 'Output file must contain at least two lines.'
    assert lines[0] == expected_line1, (
        f"Expected line 1 to be '{expected_line1}', got '{lines[0]}'."
    )

    line2 = lines[1]
    assert re.match(r'^-?\d+\.\d{4}$', line2), (
        f"Expected line 2 to be a float rounded to exactly 4 decimal places, got '{line2}'."
    )
    assert line2 == expected_line2, (
        f"Expected bootstrap mean coefficient '{expected_line2}', got '{line2}'."
    )

    coef = float(line2)
    assert 0.40 <= coef <= 0.60, (
        f'Expected bootstrap mean coefficient to be around 0.49, got {coef}.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
