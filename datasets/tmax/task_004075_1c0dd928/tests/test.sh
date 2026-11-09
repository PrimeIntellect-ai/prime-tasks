#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import stat
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, KFold

PIPELINE = Path('/home/user/pipeline.py')
CSV_PATH = Path('/home/user/data/raw/metrics.csv')
REPORT_PATH = Path('/home/user/output/report.json')
EXPECTED_KEYS = {
    'valid_row_count',
    'cpu_ram_corr_mean',
    'cpu_ram_corr_lower',
    'cpu_ram_corr_upper',
    'best_alpha',
    'best_cv_score',
}


def get_valid_row_count(filepath):
    """Manually parse and count valid rows according to the schema rules."""
    count = 0
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                cpu = float(row['cpu_usage'])
                ram = float(row['ram_usage'])
                disk = float(row['disk_io'])
                net = float(row['net_tx'])

                if (0.0 <= cpu <= 100.0 and
                    0.0 <= ram <= 100.0 and
                    disk >= 0.0 and
                    net >= 0.0):
                    count += 1
            except (ValueError, TypeError):
                # NaN or unparseable values are dropped
                pass
    return count


def calculate_expected(filepath):
    df = pd.read_csv(filepath)
    clean = df.dropna(subset=['cpu_usage', 'ram_usage', 'disk_io', 'net_tx'])
    clean = clean[
        clean['cpu_usage'].between(0.0, 100.0)
        & clean['ram_usage'].between(0.0, 100.0)
        & (clean['disk_io'] >= 0.0)
        & (clean['net_tx'] >= 0.0)
    ].copy()

    assert len(clean) >= 5, 'Verifier input unexpectedly has fewer than five valid rows'

    correlations = []
    np.random.seed(42)
    for _ in range(1000):
        indices = np.random.choice(len(clean), size=len(clean), replace=True)
        sample = clean.iloc[indices]
        correlations.append(
            np.corrcoef(sample['cpu_usage'].to_numpy(), sample['ram_usage'].to_numpy())[0, 1]
        )

    correlations = np.asarray(correlations)
    X = clean[['cpu_usage', 'ram_usage', 'disk_io']]
    y = clean['net_tx']
    cv = KFold(n_splits=5, shuffle=True, random_state=42)
    search = GridSearchCV(
        Ridge(),
        {'alpha': [0.1, 1.0, 10.0, 100.0]},
        cv=cv,
    )
    search.fit(X, y)

    return {
        'valid_row_count': int(len(clean)),
        'cpu_ram_corr_mean': round(float(np.mean(correlations)), 4),
        'cpu_ram_corr_lower': round(float(np.percentile(correlations, 2.5)), 4),
        'cpu_ram_corr_upper': round(float(np.percentile(correlations, 97.5)), 4),
        'best_alpha': float(search.best_params_['alpha']),
        'best_cv_score': round(float(search.best_score_), 4),
    }


def run_pipeline():
    assert PIPELINE.exists(), 'The file /home/user/pipeline.py was not created.'
    assert not PIPELINE.is_symlink(), '/home/user/pipeline.py must be a regular script, not a symlink.'
    mode = os.stat(PIPELINE, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), '/home/user/pipeline.py must be a regular file.'

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    if REPORT_PATH.exists() or REPORT_PATH.is_symlink():
        REPORT_PATH.unlink()

    result = subprocess.run(
        ['python3', str(PIPELINE)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'pipeline.py exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert REPORT_PATH.is_file(), 'Executing pipeline.py did not create /home/user/output/report.json.'
    assert not REPORT_PATH.is_symlink(), 'report.json must be a regular file, not a symlink.'


def load_report():
    with open(REPORT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail('report.json is not a valid JSON file.')


def assert_original_constraints(data, csv_path):
    assert set(data.keys()) == EXPECTED_KEYS, (
        f'JSON keys do not match the expected structure. Got: {list(data.keys())}'
    )

    expected_count = get_valid_row_count(csv_path)
    assert data['valid_row_count'] == expected_count, (
        f"Expected valid_row_count to be {expected_count}, got {data['valid_row_count']}"
    )

    assert isinstance(data['cpu_ram_corr_mean'], float), 'cpu_ram_corr_mean must be a float'
    assert isinstance(data['cpu_ram_corr_lower'], float), 'cpu_ram_corr_lower must be a float'
    assert isinstance(data['cpu_ram_corr_upper'], float), 'cpu_ram_corr_upper must be a float'
    assert -1.0 <= data['cpu_ram_corr_mean'] <= 1.0, 'Correlation mean must be between -1 and 1'
    assert data['cpu_ram_corr_lower'] <= data['cpu_ram_corr_mean'] <= data['cpu_ram_corr_upper'], (
        'Correlation bounds are logically inconsistent (lower <= mean <= upper)'
    )

    assert isinstance(data['best_alpha'], float), 'best_alpha must be a float'
    assert data['best_alpha'] in [0.1, 1.0, 10.0, 100.0], (
        'best_alpha must be one of the tested values [0.1, 1.0, 10.0, 100.0], '
        f"got {data['best_alpha']}"
    )
    assert isinstance(data['best_cv_score'], float), 'best_cv_score must be a float'
    assert data['best_cv_score'] <= 1.0, 'R-squared CV score cannot exceed 1.0'


def assert_exact_report(data, expected):
    assert set(data.keys()) == EXPECTED_KEYS
    for key, expected_value in expected.items():
        assert data[key] == expected_value, (
            f'Incorrect {key}: expected {expected_value!r}, got {data[key]!r}'
        )


def make_challenge_csv(path):
    seed = int.from_bytes(os.urandom(8), 'little')
    rng = np.random.default_rng(seed)
    n = 83
    cpu = rng.uniform(3.0, 97.0, n)
    ram = np.clip(18.0 + 0.58 * cpu + rng.normal(0.0, 8.0, n), 1.0, 99.0)
    disk = rng.gamma(shape=2.3, scale=24.0, size=n)
    net = 7.0 + 0.35 * cpu + 0.22 * ram + 0.72 * disk + rng.normal(0.0, 7.5, n)
    net = np.maximum(net, 0.01)

    challenge = pd.DataFrame({
        'cpu_usage': cpu,
        'ram_usage': ram,
        'disk_io': disk,
        'net_tx': net,
    })
    invalid = pd.DataFrame([
        {'cpu_usage': 101.0, 'ram_usage': 40.0, 'disk_io': 2.0, 'net_tx': 3.0},
        {'cpu_usage': 20.0, 'ram_usage': -0.1, 'disk_io': 2.0, 'net_tx': 3.0},
        {'cpu_usage': 20.0, 'ram_usage': 40.0, 'disk_io': -0.1, 'net_tx': 3.0},
        {'cpu_usage': 20.0, 'ram_usage': 40.0, 'disk_io': 2.0, 'net_tx': -0.1},
        {'cpu_usage': np.nan, 'ram_usage': 40.0, 'disk_io': 2.0, 'net_tx': 3.0},
    ])
    pd.concat([challenge, invalid], ignore_index=True).to_csv(path, index=False)


def test_00_pipeline_execution_and_computed_results():
    original_csv = CSV_PATH.read_bytes()
    original_expected = calculate_expected(CSV_PATH)
    pending_error = None

    try:
        run_pipeline()
        original_data = load_report()
        assert_original_constraints(original_data, CSV_PATH)
        assert_exact_report(original_data, original_expected)

        make_challenge_csv(CSV_PATH)
        challenge_expected = calculate_expected(CSV_PATH)
        run_pipeline()
        challenge_data = load_report()
        assert_original_constraints(challenge_data, CSV_PATH)
        assert_exact_report(challenge_data, challenge_expected)
    except BaseException as exc:
        pending_error = exc
    finally:
        CSV_PATH.write_bytes(original_csv)
        try:
            run_pipeline()
        except BaseException:
            if pending_error is None:
                raise

    if pending_error is not None:
        raise pending_error

    final_data = load_report()
    assert_exact_report(final_data, original_expected)


def test_report_json_exists():
    assert os.path.isfile('/home/user/output/report.json'), (
        'The file /home/user/output/report.json was not created.'
    )


def test_report_json_structure_and_values():
    report_path = '/home/user/output/report.json'
    assert os.path.isfile(report_path), 'report.json is missing.'
    data = load_report()
    assert_original_constraints(data, '/home/user/data/raw/metrics.csv')
    assert_exact_report(data, calculate_expected('/home/user/data/raw/metrics.csv'))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
