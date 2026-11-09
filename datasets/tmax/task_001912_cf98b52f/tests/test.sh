#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile

import numpy as np
import pandas as pd
from scipy.optimize import minimize

DATA_PATH = Path('/home/user/spatial_data.csv')
RESULTS_PATH = Path('/home/user/results.json')
EXPECTED_MODELS = {'Q1': 'A', 'Q2': 'B', 'Q3': 'B', 'Q4': 'A'}


def expected_results(df):
    masks = {
        'Q1': (df.x < 0.5) & (df.y < 0.5),
        'Q2': (df.x >= 0.5) & (df.y < 0.5),
        'Q3': (df.x < 0.5) & (df.y >= 0.5),
        'Q4': (df.x >= 0.5) & (df.y >= 0.5),
    }
    answer = {}
    for quadrant, mask in masks.items():
        part = df.loc[mask]
        assert len(part) > 0, f'{quadrant} unexpectedly contains no observations.'
        x = part.x.to_numpy(dtype=float)
        y = part.y.to_numpy(dtype=float)
        z = part.z.to_numpy(dtype=float)

        def mse_a(theta):
            prediction = theta[0] * x + theta[1] * y + theta[2]
            return float(np.mean((prediction - z) ** 2))

        def mse_b(theta):
            prediction = theta[0] * x**2 + theta[1] * y**2 + theta[2] * x * y + theta[3]
            return float(np.mean((prediction - z) ** 2))

        fit_a = minimize(mse_a, np.zeros(3), method='Nelder-Mead')
        fit_b = minimize(mse_b, np.zeros(4), method='Nelder-Mead')
        if fit_a.fun < fit_b.fun:
            answer[quadrant] = {'best_model': 'A', 'mse': round(float(fit_a.fun), 4)}
        else:
            answer[quadrant] = {'best_model': 'B', 'mse': round(float(fit_b.fun), 4)}
    return answer


def load_and_validate(expected, require_original_assertions=False):
    assert RESULTS_PATH.exists(), f'File {RESULTS_PATH} is missing. The pipeline did not produce the expected output file.'
    try:
        with RESULTS_PATH.open() as f:
            results = json.load(f)
    except json.JSONDecodeError:
        assert False, f'File {RESULTS_PATH} is not valid JSON.'

    assert isinstance(results, dict), 'The top-level JSON value must be an object.'
    assert set(results) == {'Q1', 'Q2', 'Q3', 'Q4'}, 'The results JSON must contain exactly Q1, Q2, Q3, and Q4.'

    for q in ('Q1', 'Q2', 'Q3', 'Q4'):
        assert q in results, f'Quadrant {q} is missing from the results JSON.'
        assert isinstance(results[q], dict), f'Quadrant {q} must contain a JSON object.'
        assert 'best_model' in results[q], f"'best_model' key is missing in quadrant {q}."
        assert 'mse' in results[q], f"'mse' key is missing in quadrant {q}."

        actual_model = results[q]['best_model']
        if require_original_assertions:
            expected_model = EXPECTED_MODELS[q]
            assert actual_model == expected_model, (
                f"Expected best_model for {q} to be '{expected_model}', but got '{actual_model}'. "
                'Check your domain decomposition and optimization logic.'
            )

        mse = results[q]['mse']
        assert isinstance(mse, (int, float)) and not isinstance(mse, bool), f'MSE for {q} must be a numeric value, got {type(mse).__name__}.'
        assert math.isfinite(float(mse)), f'MSE for {q} must be finite.'
        if require_original_assertions:
            assert 0.0 < mse < 1.0, f'MSE for {q} ({mse}) is outside the expected reasonable bounds. It should be small but positive.'

        assert actual_model == expected[q]['best_model'], (
            f"For {q}, the pipeline selected {actual_model}, but fitting both specified models "
            f"with Nelder-Mead selects {expected[q]['best_model']}."
        )
        assert abs(float(mse) - expected[q]['mse']) <= 1e-9, (
            f"For {q}, reported MSE {mse} does not equal the dataset-derived, four-decimal "
            f"MSE {expected[q]['mse']}."
        )
    return RESULTS_PATH.read_bytes()


def challenge_dataframe(seed, choices):
    rng = np.random.default_rng(seed)
    rows = []
    bounds = {
        'Q1': (0.03, 0.47, 0.03, 0.47),
        'Q2': (0.53, 0.97, 0.03, 0.47),
        'Q3': (0.03, 0.47, 0.53, 0.97),
        'Q4': (0.53, 0.97, 0.53, 0.97),
    }
    for index, q in enumerate(('Q1', 'Q2', 'Q3', 'Q4')):
        x0, x1, y0, y1 = bounds[q]
        x = rng.uniform(x0, x1, 90)
        y = rng.uniform(y0, y1, 90)
        if choices[q] == 'A':
            z = (1.4 + 0.3 * index) * x + (-2.1 + 0.2 * index) * y + 0.35 - 0.1 * index
        else:
            z = (2.2 + 0.4 * index) * x**2 + (-2.7 + 0.3 * index) * y**2 + (1.8 - 0.2 * index) * x * y + 0.15
        z += rng.normal(0, 0.008, len(x))
        rows.append(pd.DataFrame({'x': x, 'y': y, 'z': z}))
    return pd.concat(rows, ignore_index=True)


def test_pipeline_execution_and_results():
    assert DATA_PATH.exists(), f'Input dataset {DATA_PATH} is missing.'
    original_data_bytes = DATA_PATH.read_bytes()
    prior_results = RESULTS_PATH.read_bytes() if RESULTS_PATH.exists() else None
    original_output = None

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        trace = td / 'minimize_trace.jsonl'
        (td / 'sitecustomize.py').write_text(r'''
import json
import os
import numpy as np
import scipy.optimize as _opt
_original_minimize = _opt.minimize

def _traced_minimize(fun, x0, *args, **kwargs):
    method = kwargs.get('method', args[1] if len(args) > 1 else None)
    options = kwargs.get('options') or {}
    valid = (
        str(method).lower().replace('_', '-').replace(' ', '-') == 'nelder-mead'
        and np.asarray(x0).size in (3, 4)
        and bool(np.all(np.asarray(x0, dtype=float) == 0.0))
        and kwargs.get('tol') is None
        and 'xatol' not in options
        and 'fatol' not in options
    )
    path = os.environ.get('PIPELINE_MINIMIZE_TRACE')
    if path:
        with open(path, 'a') as f:
            f.write(json.dumps({'valid': bool(valid)}) + '\n')
    return _original_minimize(fun, x0, *args, **kwargs)

_opt.minimize = _traced_minimize
''')

        env = os.environ.copy()
        env['PYTHONPATH'] = str(td) + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
        env['PIPELINE_MINIMIZE_TRACE'] = str(trace)

        scripts = [p for p in Path('/home/user').rglob('*.py') if p.is_file()]
        assert scripts, 'No Python pipeline script was found under /home/user.'
        preferred = [p for p in scripts if 'results.json' in p.read_text(errors='ignore')]
        candidates = preferred + [p for p in scripts if p not in preferred]

        def run_script(script):
            RESULTS_PATH.unlink(missing_ok=True)
            trace.unlink(missing_ok=True)
            completed = subprocess.run(
                ['python3', str(script)], cwd='/home/user', env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
            )
            return completed

        def assert_optimizer_calls(completed):
            assert completed.returncode == 0, f'Pipeline execution failed:\n{completed.stdout}\n{completed.stderr}'
            records = []
            if trace.exists():
                for line in trace.read_text().splitlines():
                    records.append(json.loads(line))
            assert len(records) >= 8, 'The executed pipeline did not fit both models in all four quadrants using scipy.optimize.minimize.'
            assert all(record.get('valid') for record in records), 'All fits must use Nelder-Mead, all-zero initial parameters, and default tolerances.'

        try:
            original_df = pd.read_csv(DATA_PATH)
            expected_original = expected_results(original_df)
            selected = None
            selected_run = None
            for script in candidates:
                completed = run_script(script)
                if completed.returncode == 0 and RESULTS_PATH.exists():
                    selected = script
                    selected_run = completed
                    break
            assert selected is not None, 'Executing the submitted Python scripts did not produce /home/user/results.json.'
            assert_optimizer_calls(selected_run)
            original_output = load_and_validate(expected_original, require_original_assertions=True)

            challenges = [
                challenge_dataframe(731, {'Q1': 'B', 'Q2': 'A', 'Q3': 'A', 'Q4': 'B'}),
                challenge_dataframe(947, {'Q1': 'A', 'Q2': 'B', 'Q3': 'B', 'Q4': 'A'}),
            ]
            for frame in challenges:
                frame.to_csv(DATA_PATH, index=False)
                completed = run_script(selected)
                assert_optimizer_calls(completed)
                load_and_validate(expected_results(frame))
        finally:
            DATA_PATH.write_bytes(original_data_bytes)
            if original_output is not None:
                RESULTS_PATH.write_bytes(original_output)
            elif prior_results is not None:
                RESULTS_PATH.write_bytes(prior_results)
            else:
                RESULTS_PATH.unlink(missing_ok=True)
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
