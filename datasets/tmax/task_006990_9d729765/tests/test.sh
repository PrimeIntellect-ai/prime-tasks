#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -rf /tmp/verifier_instrument
mkdir -p /tmp/verifier_instrument

cat <<'PY_EOF' > /tmp/verifier_instrument/sitecustomize.py
import os
import multiprocessing
import multiprocessing.pool
import numpy as np
import scipy.integrate
import scipy.stats

_EVENT_FILE = os.environ.get("VERIFIER_EVENT_FILE")

def _record(message):
    if not _EVENT_FILE:
        return
    fd = os.open(_EVENT_FILE, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, (message + "\n").encode("utf-8"))
    finally:
        os.close(fd)

_original_seed = np.random.seed
def _seed(seed=None, *args, **kwargs):
    if seed == 42:
        _record("SEED42")
    return _original_seed(seed, *args, **kwargs)
np.random.seed = _seed

_original_pool = multiprocessing.Pool
def _pool(*args, **kwargs):
    processes = kwargs.get("processes", args[0] if args else None)
    _record("POOL:" + str(processes))
    return _original_pool(*args, **kwargs)
multiprocessing.Pool = _pool

for _method_name in ("map", "starmap", "imap", "imap_unordered", "map_async", "starmap_async", "apply_async"):
    _original_method = getattr(multiprocessing.pool.Pool, _method_name)
    def _make_wrapper(original, name):
        def _wrapper(self, *args, **kwargs):
            _record("DISPATCH:" + name)
            return original(self, *args, **kwargs)
        return _wrapper
    setattr(multiprocessing.pool.Pool, _method_name,
            _make_wrapper(_original_method, _method_name))

_original_quad = scipy.integrate.quad
_quad_seen = False
def _quad(*args, **kwargs):
    global _quad_seen
    if not _quad_seen:
        _record("QUAD")
        _quad_seen = True
    return _original_quad(*args, **kwargs)
scipy.integrate.quad = _quad

_original_ttest_rel = scipy.stats.ttest_rel
def _ttest_rel(*args, **kwargs):
    _record("TTEST_REL")
    return _original_ttest_rel(*args, **kwargs)
scipy.stats.ttest_rel = _ttest_rel
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from scipy.integrate import quad
from scipy.stats import ttest_rel

DATASET = '/home/user/dataset.csv'
STATS = '/home/user/stats.json'
EVENTS = '/tmp/verifier_events.log'


def _validate_original_dataset():
    assert os.path.isfile(DATASET), f"Dataset is missing: {DATASET}"
    df = pd.read_csv(DATASET)
    assert list(df.columns) == ['t', 'y']
    assert len(df) == 100

    expected_t = np.linspace(0.1, 5.0, 100)
    np.random.seed(123)
    expected_y = np.array([
        2.0 * quad(lambda x: np.exp(-x**2 / 2), 0, t)[0]
        + np.random.normal(0, 0.15)
        for t in expected_t
    ])
    np.testing.assert_allclose(df['t'].to_numpy(), expected_t, rtol=0, atol=1e-12)
    np.testing.assert_allclose(df['y'].to_numpy(), expected_y, rtol=0, atol=1e-12)
    return df


def _expected_result(df):
    t = df['t'].to_numpy(dtype=float)
    y = df['y'].to_numpy(dtype=float)

    model_a = np.array([
        2.0 * quad(lambda x: np.exp(-x*x / 2.0), 0, ti)[0]
        for ti in t
    ])
    model_b = np.array([
        2.5 * quad(lambda x: 1.0 if x == 0 else np.sin(x) / x, 0, ti)[0]
        for ti in t
    ])

    np.random.seed(42)
    samples = [np.random.choice(len(df), size=len(df), replace=True)
               for _ in range(50)]
    mse_a = [float(np.mean((y[idx] - model_a[idx]) ** 2)) for idx in samples]
    mse_b = [float(np.mean((y[idx] - model_b[idx]) ** 2)) for idx in samples]
    result = ttest_rel(mse_a, mse_b)
    return float(result.statistic), float(result.pvalue)


def _candidate_scripts():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '.local', '__pycache__'}]
        for name in files:
            if not name.endswith('.py'):
                continue
            path = os.path.join(root, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                source = open(path, 'r', encoding='utf-8').read()
            except (OSError, UnicodeError):
                continue
            if all(token in source for token in ('seed', 'Pool', 'quad', 'ttest_rel')):
                candidates.append(path)
    return sorted(candidates, key=lambda p: os.path.getmtime(p), reverse=True)


def _load_and_check_json(expected_stat, expected_pval):
    assert os.path.isfile(STATS), f"Results file is missing: {STATS}"
    with open(STATS, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("stats.json is not a valid JSON file.")

    assert "statistic" in data, "Key 'statistic' is missing from stats.json"
    assert "p_value" in data, "Key 'p_value' is missing from stats.json"
    assert set(data) == {'statistic', 'p_value'}, "stats.json must contain the exact required keys"

    stat = data['statistic']
    pval = data['p_value']
    assert isinstance(stat, (int, float)) and not isinstance(stat, bool), "statistic must be a number"
    assert isinstance(pval, (int, float)) and not isinstance(pval, bool), "p_value must be a number"
    assert math.isfinite(stat), "statistic must be finite"
    assert math.isfinite(pval) and pval > 0, "p_value must be finite and positive"

    # Preserve the original verifier's assertions.
    assert abs(stat - (-69.176)) < 1.0, f"statistic {stat} is not close to expected -69.176"
    assert pval < 1e-40, f"p_value {pval} is not close to expected 3.9e-51"

    # Compare against a fresh computation from the supplied dataset.
    assert math.isclose(stat, expected_stat, rel_tol=1e-9, abs_tol=1e-9), \
        f"statistic {stat} differs from recomputed value {expected_stat}"
    assert math.isclose(pval, expected_pval, rel_tol=1e-8, abs_tol=1e-300), \
        f"p_value {pval} differs from recomputed value {expected_pval}"


def test_script_is_executed_and_computation_is_correct():
    df = _validate_original_dataset()
    expected_stat, expected_pval = _expected_result(df)
    candidates = _candidate_scripts()
    assert candidates, "No Python script implementing the requested computation was found"

    original_dataset = open(DATASET, 'rb').read()
    failures = []
    for script in candidates:
        with open(DATASET, 'wb') as f:
            f.write(original_dataset)
        for path in (STATS, EVENTS):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        env = os.environ.copy()
        env['PYTHONPATH'] = '/tmp/verifier_instrument' + (
            os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
        env['VERIFIER_EVENT_FILE'] = EVENTS
        try:
            completed = subprocess.run(
                [sys.executable, script], cwd='/home/user', env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                timeout=180
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{script}: timed out")
            continue

        if completed.returncode != 0:
            failures.append(f"{script}: exited {completed.returncode}: {completed.stderr[-500:]}")
            continue

        try:
            events = open(EVENTS, 'r', encoding='utf-8').read().splitlines()
        except FileNotFoundError:
            events = []

        required = {
            'SEED42': any(e == 'SEED42' for e in events),
            'Pool with 4 workers': any(e == 'POOL:4' for e in events),
            'Pool task dispatch': any(e.startswith('DISPATCH:') for e in events),
            'scipy.integrate.quad': any(e == 'QUAD' for e in events),
            'scipy.stats.ttest_rel': any(e == 'TTEST_REL' for e in events),
        }
        missing = [name for name, present in required.items() if not present]
        if missing:
            failures.append(f"{script}: did not execute {', '.join(missing)}")
            continue

        try:
            _load_and_check_json(expected_stat, expected_pval)
            with open(DATASET, 'rb') as f:
                assert f.read() == original_dataset, "The submitted script modified dataset.csv"
            return
        except AssertionError as exc:
            failures.append(f"{script}: {exc}")

    pytest.fail("No submitted script passed execution and result checks:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
