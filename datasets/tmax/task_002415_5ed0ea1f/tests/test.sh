#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
from pathlib import Path
import subprocess

import numpy as np
import pytest

HOME = Path('/home/user')
REPORT = HOME / 'audit_report.json'
INPUT_PATHS = [
    HOME / 'embeddings.csv',
    HOME / 'targets.csv',
    HOME / 'model_artifact.txt',
]
EXPECTED_KEYS = {'ols_weights', 'artifact_weights', 'ols_mse', 'artifact_mse', 'reproducible'}


def load_report():
    assert REPORT.is_file(), f'Audit report not found at {REPORT}'
    try:
        with REPORT.open('r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'File {REPORT} is not valid JSON')


def test_audit_report_exists_and_valid():
    data = load_report()

    assert set(data.keys()) == EXPECTED_KEYS, f'JSON keys do not match expected schema. Found: {list(data.keys())}'

    # Expected values based on the fixed random seed setup
    expected_ols_weights = [1.4883, -1.9962, 0.4996]
    expected_artifact_weights = [1.6, -2.05, 0.7]
    expected_ols_mse = 0.0083
    expected_artifact_mse = 0.0573
    expected_reproducible = False

    assert len(data['ols_weights']) == 3, 'ols_weights must have exactly 3 elements'
    for i, (val, exp) in enumerate(zip(data['ols_weights'], expected_ols_weights)):
        assert abs(val - exp) <= 0.0002, f'ols_weights[{i}] is {val}, expected {exp}'

    assert len(data['artifact_weights']) == 3, 'artifact_weights must have exactly 3 elements'
    for i, (val, exp) in enumerate(zip(data['artifact_weights'], expected_artifact_weights)):
        assert abs(val - exp) <= 0.0002, f'artifact_weights[{i}] is {val}, expected {exp}'

    assert abs(data['ols_mse'] - expected_ols_mse) <= 0.0002, f"ols_mse is {data['ols_mse']}, expected {expected_ols_mse}"
    assert abs(data['artifact_mse'] - expected_artifact_mse) <= 0.0002, f"artifact_mse is {data['artifact_mse']}, expected {expected_artifact_mse}"
    assert data['reproducible'] is expected_reproducible, f"reproducible is {data['reproducible']}, expected {expected_reproducible}"


def candidate_scripts():
    candidates = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path == REPORT or path in INPUT_PATHS:
            continue
        if path.suffix == '.py':
            candidates.append(path)
            continue
        try:
            first_line = path.open('rb').readline(256).lower()
        except OSError:
            continue
        if first_line.startswith(b'#!') and b'python' in first_line:
            candidates.append(path)
    return sorted(set(candidates))


def expected_report(X, y, artifact):
    ols = np.linalg.inv(X.T @ X) @ X.T @ y
    ols_mse = float(np.mean((X @ ols - y) ** 2))
    artifact_mse = float(np.mean((X @ artifact - y) ** 2))
    return {
        'ols_weights': [round(float(v), 4) for v in ols],
        'artifact_weights': [round(float(v), 4) for v in artifact],
        'ols_mse': round(ols_mse, 4),
        'artifact_mse': round(artifact_mse, 4),
        'reproducible': abs(ols_mse - artifact_mse) < 1e-5,
    }, ols


def validate_dynamic_report(expected):
    data = load_report()
    assert set(data.keys()) == EXPECTED_KEYS
    assert isinstance(data['ols_weights'], list) and len(data['ols_weights']) == 3
    assert isinstance(data['artifact_weights'], list) and len(data['artifact_weights']) == 3

    for key in ('ols_weights', 'artifact_weights'):
        for actual, wanted in zip(data[key], expected[key]):
            assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
            assert math.isfinite(float(actual))
            assert abs(float(actual) - wanted) <= 0.000051

    for key in ('ols_mse', 'artifact_mse'):
        actual = data[key]
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
        assert math.isfinite(float(actual))
        assert abs(float(actual) - expected[key]) <= 0.000051

    assert isinstance(data['reproducible'], bool)
    assert data['reproducible'] is expected['reproducible']


def run_case(script, X, y, artifact):
    expected, _ = expected_report(X, y, artifact)
    np.savetxt(INPUT_PATHS[0], X, delimiter=',')
    np.savetxt(INPUT_PATHS[1], y, delimiter=',')
    np.savetxt(INPUT_PATHS[2], artifact.reshape(1, -1), delimiter=',')
    REPORT.unlink(missing_ok=True)
    result = subprocess.run(
        ['python3', str(script)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f'{script} exited with {result.returncode}: {result.stderr}'
    validate_dynamic_report(expected)


def test_submitted_python_script_recomputes_audit():
    scripts = candidate_scripts()
    assert scripts, 'No Python audit script was found under /home/user'

    originals = {path: path.read_bytes() for path in INPUT_PATHS}
    original_report = REPORT.read_bytes()
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), 'big'))
    X = rng.normal(size=(137, 3))
    true_w = rng.uniform(-3.0, 3.0, size=3)
    y = X @ true_w + rng.normal(scale=0.17, size=137)
    _, ols = expected_report(X, y, true_w)

    failures = []
    try:
        for script in scripts:
            try:
                run_case(script, X, y, ols + np.array([0.4, -0.3, 0.25]))
                run_case(script, X, y, ols.copy())
                return
            except Exception as exc:
                failures.append(f'{script}: {exc}')
        pytest.fail('No submitted Python script generated correct reports when executed on fresh inputs. ' + ' | '.join(failures))
    finally:
        for path, contents in originals.items():
            path.write_bytes(contents)
        REPORT.write_bytes(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
