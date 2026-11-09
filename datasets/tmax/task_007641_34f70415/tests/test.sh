#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import csv
import json
import math
import os
import stat
import subprocess

import numpy as np
import pytest

SCRIPT = '/home/user/pipeline.sh'
CSV_PATH = '/home/user/inference_logs.csv'
REPORT = '/home/user/report.json'
REQUIRED_KEYS = {
    'model_A_cleaned_count',
    'model_B_cleaned_count',
    'mean_diff_observed',
    'ci_lower',
    'ci_upper',
}


def original_rows():
    rs = np.random.RandomState(100)
    a = rs.normal(loc=45.0, scale=5.0, size=120)
    b = rs.normal(loc=52.0, scale=6.0, size=130)
    a[5] = -10.5
    a[12] = np.nan
    a[45] = 200.0
    a[60] = 195.0
    b[10] = -2.0
    b[22] = np.nan
    b[23] = np.nan
    b[80] = 300.0
    b[100] = 280.0

    rows = []
    for i, value in enumerate(a):
        rows.append([f'A_{i}', 'A', 'NA' if np.isnan(value) else str(round(float(value), 2))])
    for i, value in enumerate(b):
        rows.append([f'B_{i}', 'B', 'NA' if np.isnan(value) else str(round(float(value), 2))])
    permutation = np.random.RandomState(42).permutation(len(rows))
    return [rows[i] for i in permutation]


def alternate_rows():
    rs = np.random.RandomState(731)
    a = np.round(rs.normal(31.0, 4.2, 95), 2)
    b = np.round(rs.normal(43.5, 5.1, 103), 2)
    rows = [[f'X_A_{i}', 'A', str(float(v))] for i, v in enumerate(a)]
    rows += [[f'X_B_{i}', 'B', str(float(v))] for i, v in enumerate(b)]
    rows += [
        ['bad_a_neg', 'A', '-8.5'],
        ['bad_a_na', 'A', 'NA'],
        ['bad_a_empty', 'A', ''],
        ['bad_a_high', 'A', '410.0'],
        ['bad_b_neg', 'B', '-1.0'],
        ['bad_b_na', 'B', 'NA'],
        ['bad_b_empty', 'B', ''],
        ['bad_b_high', 'B', '525.0'],
    ]
    permutation = np.random.RandomState(19).permutation(len(rows))
    return [rows[i] for i in permutation]


def write_input(rows):
    with open(CSV_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['req_id', 'model', 'latency'])
        writer.writerows(rows)


def cleaned_values(rows):
    values = {'A': [], 'B': []}
    for _, model, raw in rows:
        if raw in ('NA', ''):
            continue
        try:
            value = float(raw)
        except ValueError:
            continue
        if value >= 0:
            values[model].append(value)

    cleaned = {}
    for model in ('A', 'B'):
        data = np.asarray(values[model], dtype=float)
        q1 = np.percentile(data, 25)
        q3 = np.percentile(data, 75)
        iqr = q3 - q1
        lower = q1 - 1.5 * iqr
        upper = q3 + 1.5 * iqr
        cleaned[model] = data[(data >= lower) & (data <= upper)]
    return cleaned


def bootstrap_candidates(a, b):
    candidates = []

    # Accept either common call order. Both obey the required seed and perform
    # exactly 10,000 replacement-resampling iterations.
    for first in ('B', 'A'):
        np.random.seed(42)
        diffs = np.empty(10000)
        for i in range(10000):
            if first == 'B':
                sample_b = np.random.choice(b, size=len(b), replace=True)
                sample_a = np.random.choice(a, size=len(a), replace=True)
            else:
                sample_a = np.random.choice(a, size=len(a), replace=True)
                sample_b = np.random.choice(b, size=len(b), replace=True)
            diffs[i] = sample_b.mean() - sample_a.mean()
        candidates.append(tuple(np.percentile(diffs, [2.5, 97.5])))

    # Also accept equivalent vectorized NumPy implementations.
    for first in ('B', 'A'):
        np.random.seed(42)
        if first == 'B':
            samples_b = np.random.choice(b, size=(10000, len(b)), replace=True)
            samples_a = np.random.choice(a, size=(10000, len(a)), replace=True)
        else:
            samples_a = np.random.choice(a, size=(10000, len(a)), replace=True)
            samples_b = np.random.choice(b, size=(10000, len(b)), replace=True)
        diffs = samples_b.mean(axis=1) - samples_a.mean(axis=1)
        candidates.append(tuple(np.percentile(diffs, [2.5, 97.5])))

    return candidates


def validate_report(rows):
    cleaned = cleaned_values(rows)
    count_a = len(cleaned['A'])
    count_b = len(cleaned['B'])
    mean_diff = cleaned['B'].mean() - cleaned['A'].mean()
    ci_candidates = bootstrap_candidates(cleaned['A'], cleaned['B'])

    assert os.path.isfile(REPORT), f'Expected report {REPORT} does not exist.'
    try:
        with open(REPORT) as f:
            report = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'File {REPORT} is not valid JSON.')

    assert set(report.keys()) == REQUIRED_KEYS, f'JSON must contain exactly the keys: {REQUIRED_KEYS}'
    assert report['model_A_cleaned_count'] == count_a
    assert report['model_B_cleaned_count'] == count_b
    assert abs(report['mean_diff_observed'] - mean_diff) <= 0.02

    lower = report['ci_lower']
    upper = report['ci_upper']
    assert math.isfinite(lower) and math.isfinite(upper)
    assert any(
        abs(lower - expected_lower) <= 0.05 and abs(upper - expected_upper) <= 0.05
        for expected_lower, expected_upper in ci_candidates
    ), f'Bootstrap CI {(lower, upper)} does not match the recomputed 10,000-iteration seeded CI {ci_candidates}'


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f'Expected script {SCRIPT} does not exist.'
    mode = os.stat(SCRIPT).st_mode
    assert bool(mode & stat.S_IXUSR), f'Script {SCRIPT} is not executable.'


def test_pipeline_executes_and_generates_correct_reports():
    for rows in (original_rows(), alternate_rows()):
        write_input(rows)
        if os.path.exists(REPORT):
            os.remove(REPORT)
        result = subprocess.run(
            [SCRIPT],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f'Pipeline failed with exit {result.returncode}:\n{result.stderr}'
        validate_report(rows)
PY

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
