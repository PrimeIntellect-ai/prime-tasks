#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_analysis.py
import json
import math
import os
import pathlib
import re
import subprocess
import sys

import numpy as np
import pandas as pd
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

HOME = pathlib.Path('/home/user')
DATA = HOME / 'sensor_data.csv'
REPORT = HOME / 'analysis_report.json'
THREAD_VARS = (
    'OMP_NUM_THREADS',
    'OPENBLAS_NUM_THREADS',
    'MKL_NUM_THREADS',
    'VECLIB_MAXIMUM_THREADS',
    'NUMEXPR_NUM_THREADS',
)
NUMBER_RE = re.compile(r'-?(?:0|[1-9][0-9]*)\.[0-9]{4}\Z')

class NumberToken(str):
    pass

def load_and_check_format(path):
    text = path.read_text()
    try:
        report = json.loads(text)
        raw = json.loads(text, parse_float=NumberToken, parse_int=NumberToken)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{path} is not a valid JSON file: {exc}')

    assert set(report) == {'dropped_features', 'mse', 'model_weights'}, \
        'Report must contain exactly dropped_features, mse, and model_weights.'
    assert isinstance(raw.get('mse'), NumberToken), "'mse' must be a JSON number with four decimal places."
    assert NUMBER_RE.fullmatch(raw['mse']), "'mse' must be represented with exactly 4 decimal places."
    assert isinstance(raw.get('model_weights'), dict), "'model_weights' must be a dictionary."
    for feature, value in raw['model_weights'].items():
        assert isinstance(value, NumberToken), f"Weight for '{feature}' must be a JSON number."
        assert NUMBER_RE.fullmatch(value), f"Weight for '{feature}' must be represented with exactly 4 decimal places."
    return report

def check_original_report():
    assert REPORT.exists(), f'File {REPORT} does not exist.'
    assert REPORT.is_file(), f'{REPORT} is not a file.'
    report = load_and_check_format(REPORT)

    assert 'dropped_features' in report, "Missing 'dropped_features' in the report."
    assert 'mse' in report, "Missing 'mse' in the report."
    assert 'model_weights' in report, "Missing 'model_weights' in the report."

    expected_dropped = ['f2', 'f5']
    actual_dropped = sorted(report['dropped_features'])
    assert actual_dropped == expected_dropped, f'Expected dropped features {expected_dropped}, got {actual_dropped}'

    expected_mse = 0.2081
    actual_mse = report['mse']
    assert isinstance(actual_mse, (int, float)), "'mse' must be a number."
    assert math.isclose(actual_mse, expected_mse, abs_tol=0.0005), \
        f'MSE mismatch. Expected ~{expected_mse}, got {actual_mse}'

    expected_weights = {'f1': 1.8845, 'f3': 1.4870, 'f4': -0.4996}
    actual_weights = report['model_weights']
    assert isinstance(actual_weights, dict), "'model_weights' must be a dictionary."
    for key, value in expected_weights.items():
        assert key in actual_weights, f"Missing weight for feature '{key}'."
        assert isinstance(actual_weights[key], (int, float)), f"Weight for '{key}' must be a number."
        assert math.isclose(actual_weights[key], value, abs_tol=0.0005), \
            f"Weight mismatch for '{key}'. Expected ~{value}, got {actual_weights[key]}"
    extra_weights = set(actual_weights) - set(expected_weights)
    assert not extra_weights, f"Unexpected weights in 'model_weights': {extra_weights}"

def expected_for(path):
    frame = pd.read_csv(path)
    features = list(frame.columns[:-1])
    corr = frame[features].corr(method='pearson')
    dropped = set()
    for i, first in enumerate(features):
        for later in features[i + 1:]:
            if abs(float(corr.loc[first, later])) > 0.85:
                dropped.add(later)
    remaining = [name for name in features if name not in dropped]
    model = Ridge(alpha=1.0, fit_intercept=True)
    model.fit(frame[remaining], frame['y'])
    predictions = model.predict(frame[remaining])
    return sorted(dropped), round(float(mean_squared_error(frame['y'], predictions)), 4), {
        name: round(float(weight), 4) for name, weight in zip(remaining, model.coef_)
    }

def check_dynamic_report(expected):
    assert REPORT.exists() and REPORT.is_file(), 'Analysis script did not create analysis_report.json.'
    report = load_and_check_format(REPORT)
    dropped, mse, weights = expected
    assert sorted(report.get('dropped_features', [])) == dropped, \
        f'Dropped features on verification data are incorrect: {report.get("dropped_features")}'
    assert isinstance(report.get('mse'), (int, float)), "'mse' must be a number."
    assert math.isclose(report['mse'], mse, rel_tol=0, abs_tol=0.00005), \
        f'Expected rounded MSE {mse:.4f}, got {report["mse"]}'
    assert isinstance(report.get('model_weights'), dict), "'model_weights' must be a dictionary."
    assert set(report['model_weights']) == set(weights), 'Model weight feature names are incorrect.'
    for name, value in weights.items():
        actual = report['model_weights'][name]
        assert isinstance(actual, (int, float)), f"Weight for '{name}' must be a number."
        assert math.isclose(actual, value, rel_tol=0, abs_tol=0.00005), \
            f'Expected weight {name}={value:.4f}, got {actual}'

def candidate_scripts():
    found = set()
    for path in HOME.rglob('*'):
        if not path.is_file() or path in (DATA, REPORT):
            continue
        if path.suffix == '.py':
            found.add(path)
            continue
        try:
            first = path.open('rb').readline(256).lower()
            if first.startswith(b'#!') and b'python' in first:
                found.add(path)
        except OSError:
            pass
    return sorted(found)

WRAPPER = r'''
import os, runpy, sys
required = ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS')
assert all(os.environ.get(name) == '1' for name in required)
# Import the numerical stack only after confirming its thread-limiting environment.
import numpy, pandas
from sklearn.linear_model import Ridge
script = sys.argv[1]
sys.argv = [script]
runpy.run_path(script, run_name='__main__')
from threadpoolctl import threadpool_info
bad = [item for item in threadpool_info() if item.get('num_threads', 1) != 1]
assert not bad, 'Numerical libraries used more than one thread: %r' % (bad,)
'''

def run_script(path):
    env = os.environ.copy()
    for name in THREAD_VARS:
        env[name] = '1'
    result = subprocess.run(
        [sys.executable, '-c', WRAPPER, str(path)],
        cwd=str(HOME), env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=45
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr[-2000:] or result.stdout[-2000:] or 'script failed')

def make_challenge():
    rng = np.random.default_rng()
    n = 137
    f1 = rng.normal(size=n)
    f2 = 1.7 * f1 + rng.normal(scale=0.04, size=n)
    f3 = rng.normal(size=n)
    f4 = rng.normal(size=n)
    f5 = -2.2 * f3 + rng.normal(scale=0.05, size=n)
    y = -0.8 * f1 + 2.35 * f3 + 0.73 * f4 + rng.normal(scale=0.31, size=n)
    return pd.DataFrame({'f1': f1, 'f2': f2, 'f3': f3, 'f4': f4, 'f5': f5, 'y': y})

def main():
    check_original_report()
    scripts = candidate_scripts()
    assert scripts, 'No Python analysis script was found under /home/user.'

    original_data = DATA.read_bytes()
    original_report = REPORT.read_bytes()
    challenge = make_challenge()
    challenge.to_csv(DATA, index=False)
    challenge_expected = expected_for(DATA)
    failures = []
    try:
        for script in scripts:
            try:
                if REPORT.exists():
                    REPORT.unlink()
                run_script(script)
                check_dynamic_report(challenge_expected)

                DATA.write_bytes(original_data)
                if REPORT.exists():
                    REPORT.unlink()
                run_script(script)
                check_original_report()
                return
            except Exception as exc:
                failures.append(f'{script}: {exc}')
                challenge.to_csv(DATA, index=False)
        raise AssertionError('No submitted Python script regenerated correct reports while constrained to one thread. ' + ' | '.join(failures))
    finally:
        DATA.write_bytes(original_data)
        REPORT.write_bytes(original_report)

if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_analysis.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
