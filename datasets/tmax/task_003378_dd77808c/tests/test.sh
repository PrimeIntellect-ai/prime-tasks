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

import numpy as np
import pandas as pd
import pytest
from scipy.stats import ttest_ind
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GridSearchCV

REPORT_PATH = Path('/home/user/analysis_report.json')
DATA_PATH = Path('/home/user/sensor_data.csv')
EXPECTED_KEYS = {'p_value', 'best_max_depth', 'best_cv_accuracy'}


def compute_expected(data_path):
    df = pd.read_csv(data_path)
    df['temp_vib_ratio'] = df['temperature'] / df['vibration']
    failed = df.loc[df['failed'] == 1, 'temp_vib_ratio']
    not_failed = df.loc[df['failed'] == 0, 'temp_vib_ratio']
    p_value = float(ttest_ind(failed, not_failed, equal_var=False).pvalue)

    features = ['temperature', 'vibration', 'rotation_speed', 'temp_vib_ratio']
    search = GridSearchCV(
        RandomForestClassifier(random_state=42),
        {'max_depth': [3, 5, None]},
        cv=3,
        scoring='accuracy',
    )
    search.fit(df[features], df['failed'])
    return {
        'p_value': p_value,
        'best_max_depth': search.best_params_['max_depth'],
        'best_cv_accuracy': float(search.best_score_),
    }


def load_and_validate_report():
    assert REPORT_PATH.exists(), f'File not found: {REPORT_PATH}'
    assert REPORT_PATH.is_file(), f'Path is not a file: {REPORT_PATH}'
    with REPORT_PATH.open() as f:
        data = json.load(f)
    assert set(data.keys()) == EXPECTED_KEYS
    assert isinstance(data['p_value'], float) and math.isfinite(data['p_value'])
    assert data['best_max_depth'] is None or isinstance(data['best_max_depth'], int)
    assert isinstance(data['best_cv_accuracy'], float) and math.isfinite(data['best_cv_accuracy'])
    return data


def assert_matches_expected(actual, expected):
    assert math.isclose(actual['p_value'], expected['p_value'], rel_tol=1e-9, abs_tol=1e-300), \
        f"p_value {actual['p_value']} != recomputed value {expected['p_value']}"
    assert actual['best_max_depth'] == expected['best_max_depth'], \
        f"best_max_depth {actual['best_max_depth']} != recomputed value {expected['best_max_depth']}"
    assert math.isclose(actual['best_cv_accuracy'], expected['best_cv_accuracy'], rel_tol=0, abs_tol=1e-12), \
        f"best_cv_accuracy {actual['best_cv_accuracy']} != recomputed value {expected['best_cv_accuracy']}"


def make_variant(seed, n):
    rng = np.random.default_rng(seed)
    temperature = rng.normal(67 + seed % 5, 12, n)
    vibration = np.clip(rng.normal(4.5 + (seed % 3) * 0.4, 1.7, n), 0.35, None)
    rotation_speed = rng.normal(1450 + seed % 80, 240, n)
    logit = -4.7 + 0.045 * temperature + 0.72 * vibration - 0.0011 * rotation_speed
    probability = 1.0 / (1.0 + np.exp(-logit))
    failed = rng.binomial(1, probability)
    if failed.sum() < 6:
        failed[np.argsort(probability)[-6:]] = 1
    if (failed == 0).sum() < 6:
        failed[np.argsort(probability)[:6]] = 0
    return pd.DataFrame({
        'id': np.arange(1, n + 1),
        'temperature': temperature,
        'vibration': vibration,
        'rotation_speed': rotation_speed,
        'failed': failed,
    })


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in {'venv', '.venv', 'site-packages', '__pycache__'}]
        for name in files:
            if name.endswith('.py'):
                scripts.append(Path(root) / name)
    return sorted(scripts)


def run_script(script):
    if REPORT_PATH.exists():
        REPORT_PATH.unlink()
    result = subprocess.run(
        [sys.executable, str(script)],
        cwd=str(script.parent),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    if result.returncode != 0:
        raise AssertionError(f'{script} exited with {result.returncode}: {result.stderr[-1000:]}')
    return load_and_validate_report()


@pytest.fixture(scope='session', autouse=True)
def execute_and_verify_analysis_script():
    original_data = DATA_PATH.read_bytes()
    scripts = find_python_scripts()
    assert scripts, 'No Python analysis script was created under /home/user'

    entropy = int.from_bytes(os.urandom(4), 'little')
    variants = [
        make_variant(entropy, 223),
        make_variant(entropy ^ 0x5A17C9E3, 257),
    ]
    errors = []
    successful_script = None

    try:
        for script in scripts:
            try:
                for variant in variants:
                    variant.to_csv(DATA_PATH, index=False)
                    expected = compute_expected(DATA_PATH)
                    actual = run_script(script)
                    assert_matches_expected(actual, expected)

                DATA_PATH.write_bytes(original_data)
                expected = compute_expected(DATA_PATH)
                actual = run_script(script)
                assert_matches_expected(actual, expected)
                successful_script = script
                break
            except Exception as exc:
                errors.append(f'{script}: {exc}')

        assert successful_script is not None, 'No created Python script correctly executed the required pipeline. ' + ' | '.join(errors[-5:])
    finally:
        DATA_PATH.write_bytes(original_data)

    # Ensure the final report is freshly produced for the required original dataset.
    expected = compute_expected(DATA_PATH)
    actual = run_script(successful_script)
    assert_matches_expected(actual, expected)


def test_analysis_report_exists():
    """Check if the analysis report JSON file was created."""
    assert os.path.exists(REPORT_PATH), f"File not found: {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Path is not a file: {REPORT_PATH}"


def test_analysis_report_format():
    """Verify that the JSON file contains the correct keys and types."""
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    expected_keys = {"p_value", "best_max_depth", "best_cv_accuracy"}
    assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, but got {set(data.keys())}"

    assert isinstance(data["p_value"], float), "p_value must be a float"
    assert data["best_max_depth"] is None or isinstance(data["best_max_depth"], int), "best_max_depth must be an integer or null"
    assert isinstance(data["best_cv_accuracy"], float), "best_cv_accuracy must be a float"


def test_analysis_report_values():
    """Verify the computed metrics are correct based on the deterministic dataset."""
    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    p_val = data["p_value"]
    best_max_depth = data["best_max_depth"]
    best_cv_acc = data["best_cv_accuracy"]

    # The expected p-value is approximately 1.22e-15
    assert p_val < 1e-10, f"p_value {p_val} is too high. Expected a very small value (~1.22e-15)."
    assert p_val > 0, f"p_value {p_val} cannot be zero or negative."

    # The expected best max_depth is 3
    assert best_max_depth == 3, f"best_max_depth is {best_max_depth}, expected 3."

    # The expected cross-validation accuracy is approximately 0.762
    assert 0.70 < best_cv_acc < 0.85, f"best_cv_accuracy {best_cv_acc} is out of expected range (~0.762)."


def test_values_match_independent_recomputation():
    """Recompute every requested metric from the supplied dataset."""
    actual = load_and_validate_report()
    expected = compute_expected(DATA_PATH)
    assert_matches_expected(actual, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
