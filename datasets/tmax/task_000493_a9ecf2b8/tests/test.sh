#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import subprocess
import sys

import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.metrics import brier_score_loss
from sklearn.naive_bayes import GaussianNB
from sklearn.preprocessing import StandardScaler

CSV_PATH = '/home/user/system_metrics.csv'
REPORT_PATH = '/home/user/report.json'
FEATURES = ['cpu_usage', 'mem_usage', 'disk_io', 'net_in', 'net_out']
EXPECTED_KEYS = ['imputed_cpu_median', 'pca_explained_variance_ratio', 'brier_score']


class FloatToken(float):
    def __new__(cls, token):
        obj = float.__new__(cls, token)
        obj.token = token
        return obj


class IntToken(int):
    def __new__(cls, token):
        obj = int.__new__(cls, token)
        obj.token = token
        return obj


def expected_values(csv_path):
    df = pd.read_csv(csv_path)
    x = df[FEATURES].copy()
    cpu_median = float(x['cpu_usage'].median(skipna=True))

    for column in FEATURES:
        x[column] = x[column].fillna(x[column].median(skipna=True))
    for column in FEATURES:
        x[column] = x[column].clip(upper=x[column].quantile(0.99))

    scaled = StandardScaler().fit_transform(x)
    pca = PCA(n_components=2, random_state=42)
    components = pca.fit_transform(scaled)

    y = df['crashed'].to_numpy()
    model = GaussianNB().fit(components, y)
    class_one = list(model.classes_).index(1)
    probabilities = model.predict_proba(components)[:, class_one]

    return {
        'imputed_cpu_median': round(cpu_median, 4),
        'pca_explained_variance_ratio': [
            round(float(pca.explained_variance_ratio_[0]), 4),
            round(float(pca.explained_variance_ratio_[1]), 4),
        ],
        'brier_score': round(float(brier_score_loss(y, probabilities)), 4),
    }


def load_and_validate_report(csv_path):
    assert os.path.exists(REPORT_PATH), f'The file {REPORT_PATH} does not exist. Ensure you saved your output.'
    assert os.path.isfile(REPORT_PATH), f'The path {REPORT_PATH} is not a file.'

    with open(REPORT_PATH, 'r', encoding='utf-8') as handle:
        raw = handle.read()
    try:
        report = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'The file {REPORT_PATH} does not contain valid JSON: {exc}')

    assert isinstance(report, dict), 'report.json must contain a JSON object.'
    for key in EXPECTED_KEYS:
        assert key in report, f"Key '{key}' is missing from {REPORT_PATH}."
    assert len(report) == 3 and set(report) == set(EXPECTED_KEYS), \
        'report.json must contain exactly the three requested keys.'

    expected = expected_values(csv_path)

    actual_median = report['imputed_cpu_median']
    assert isinstance(actual_median, (int, float)) and not isinstance(actual_median, bool), \
        'imputed_cpu_median must be a float.'
    assert math.isclose(actual_median, expected['imputed_cpu_median'], abs_tol=1e-3), \
        f"imputed_cpu_median is incorrect. Expected {expected['imputed_cpu_median']}, got {actual_median}."

    pca_evr = report['pca_explained_variance_ratio']
    assert isinstance(pca_evr, list), 'pca_explained_variance_ratio must be a list.'
    assert len(pca_evr) == 2, 'pca_explained_variance_ratio must contain exactly 2 elements.'
    assert all(isinstance(value, (int, float)) and not isinstance(value, bool) for value in pca_evr), \
        'Elements of pca_explained_variance_ratio must be floats.'
    for index in range(2):
        assert math.isclose(pca_evr[index], expected['pca_explained_variance_ratio'][index], abs_tol=1e-2), \
            f'PCA explained variance ratio {index} is incorrect.'

    actual_brier = report['brier_score']
    assert isinstance(actual_brier, (int, float)) and not isinstance(actual_brier, bool), \
        'brier_score must be a float.'
    assert math.isclose(actual_brier, expected['brier_score'], abs_tol=1e-2), \
        f"brier_score is incorrect. Expected {expected['brier_score']}, got {actual_brier}."

    # Require the correctly rounded values, rather than merely accepting the old loose tolerances.
    assert actual_median == expected['imputed_cpu_median']
    assert pca_evr == expected['pca_explained_variance_ratio']
    assert actual_brier == expected['brier_score']

    try:
        tokenized = json.loads(
            raw,
            parse_float=FloatToken,
            parse_int=IntToken,
            parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)),
        )
    except (json.JSONDecodeError, ValueError) as exc:
        raise AssertionError(f'report.json contains an invalid numeric value: {exc}')

    numeric_tokens = [
        tokenized['imputed_cpu_median'],
        tokenized['pca_explained_variance_ratio'][0],
        tokenized['pca_explained_variance_ratio'][1],
        tokenized['brier_score'],
    ]
    for value in numeric_tokens:
        assert isinstance(value, FloatToken), 'Every reported value must be written as a JSON float.'
        assert re.fullmatch(r'-?\d+\.\d{4}', value.token), \
            f"Value '{value.token}' must be written with exactly four decimal places."


def make_case(seed, n, shift):
    rng = np.random.default_rng(seed)
    latent = rng.normal(size=n)
    cpu = 42 + shift + 13 * latent + rng.normal(0, 5, n)
    mem = 55 - shift / 2 + 9 * latent + rng.normal(0, 9, n)
    disk = rng.lognormal(4.0 + shift / 100, 0.8, n) + 8 * np.maximum(latent, 0)
    net_in = rng.poisson(np.maximum(40, 430 + 28 * latent), n).astype(float)
    net_out = 0.55 * net_in + rng.poisson(220, n) + rng.normal(0, 8, n)
    crashed = (1.15 * latent + rng.normal(0, 0.7, n) > 0.15).astype(int)

    columns = [cpu, mem, disk, net_in, net_out]
    for index, values in enumerate(columns):
        missing = rng.choice(n, 4 + index, replace=False)
        values[missing] = np.nan
        available = np.setdiff1d(np.arange(n), missing)
        outliers = rng.choice(available, 3, replace=False)
        values[outliers] = (index + 2) * 10000 + shift

    return pd.DataFrame({
        'cpu_usage': cpu,
        'mem_usage': mem,
        'disk_io': disk,
        'net_in': net_in,
        'net_out': net_out,
        'crashed': crashed,
    })


def find_python_scripts():
    roots = ['/home/user', '/root', '/tmp', '/workspace']
    excluded_dirs = {'.cache', '.local', '__pycache__', 'site-packages', '.git', 'tests'}
    scripts = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in excluded_dirs]
            for name in files:
                path = os.path.join(current, name)
                if not name.endswith('.py') or path == '/tmp/test_final_state.py':
                    continue
                if os.path.isfile(path) and not os.path.islink(path) and os.path.getsize(path) <= 1024 * 1024:
                    scripts.append(path)
    return sorted(set(scripts), key=lambda path: os.stat(path).st_mtime_ns, reverse=True)[:50]


def script_passes(script, cases):
    for case in cases:
        case.to_csv(CSV_PATH, index=False)
        if os.path.lexists(REPORT_PATH):
            os.remove(REPORT_PATH)
        try:
            result = subprocess.run(
                [sys.executable, script],
                cwd=os.path.dirname(script) or '/',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=45,
                check=False,
            )
            if result.returncode != 0:
                return False
            load_and_validate_report(CSV_PATH)
        except (AssertionError, OSError, subprocess.SubprocessError):
            return False
    return True


def test_report_and_executed_pipeline():
    # Preserve all original report checks, but derive every expected value from the input.
    load_and_validate_report(CSV_PATH)

    scripts = find_python_scripts()
    assert scripts, 'No Python analysis script was found.'

    with open(CSV_PATH, 'rb') as handle:
        original_csv = handle.read()
    with open(REPORT_PATH, 'rb') as handle:
        original_report = handle.read()

    seed = int.from_bytes(secrets.token_bytes(8), 'big')
    cases = [make_case(seed, 173, 7.0), make_case(seed ^ 0x9E3779B97F4A7C15, 229, -11.0)]

    try:
        passing_script = any(script_passes(script, cases) for script in scripts)
        assert passing_script, \
            'No submitted Python script reproduced the required pipeline on verifier-generated datasets.'
    finally:
        with open(CSV_PATH, 'wb') as handle:
            handle.write(original_csv)
        with open(REPORT_PATH, 'wb') as handle:
            handle.write(original_report)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
