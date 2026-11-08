#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import json
import math
import os
import shutil
import stat
import subprocess
import tempfile
import time
from pathlib import Path

import numpy as np

HOME = Path('/home/user')
TRAIN = HOME / 'train_data.csv'
TEST = HOME / 'test_data.csv'
RESULTS = HOME / 'results.json'


def pca_answer(train, test):
    mean = train.mean(axis=0)
    std = train.std(axis=0)
    assert np.all(std > 0), 'Dataset contains a constant feature'
    ztrain = (train - mean) / std
    ztest = (test - mean) / std
    _, singular_values, vt = np.linalg.svd(ztrain, full_matrices=False)
    ratios = singular_values ** 2 / np.sum(singular_values ** 2)
    cumulative = np.cumsum(ratios)
    k = int(np.searchsorted(cumulative, 0.90, side='right') + 1)
    return k, float(cumulative[k - 1]), ztest, vt[:k].T


def load_result():
    assert RESULTS.is_file(), f'Expected results file at {RESULTS} is missing.'
    try:
        with RESULTS.open('r') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {RESULTS} is not valid JSON: {exc}')

    required = {'k', 'variance_explained', 'benchmark_ms'}
    missing = required - set(data.keys())
    assert not missing, f'Missing required keys in JSON: {missing}'

    k = data.get('k')
    variance = data.get('variance_explained')
    benchmark = data.get('benchmark_ms')
    assert isinstance(k, int) and not isinstance(k, bool), f"'k' must be an integer, got {type(k)}"
    assert isinstance(variance, float), f"'variance_explained' must be a float, got {type(variance)}"
    assert isinstance(benchmark, (int, float)) and not isinstance(benchmark, bool), \
        f"'benchmark_ms' must be a number, got {type(benchmark)}"
    assert math.isfinite(variance), "'variance_explained' must be finite"
    assert math.isfinite(float(benchmark)), "'benchmark_ms' must be finite"
    assert benchmark > 0, f'Expected benchmark_ms to be a positive number, got {benchmark}'
    return data


def check_result(expected_k, expected_variance, ztest, components, elapsed):
    data = load_result()
    assert data['k'] == expected_k, f"Expected k to be {expected_k}, got {data['k']}"
    assert math.isclose(data['variance_explained'], expected_variance, rel_tol=1e-8, abs_tol=1e-8), \
        f"Expected variance_explained {expected_variance}, got {data['variance_explained']}"
    assert 0.90 < data['variance_explained'] <= 1.0

    # Independently perform the required 100 projection multiplications and use
    # their timing to reject physically implausible self-reported measurements.
    start = time.perf_counter()
    out = None
    for _ in range(100):
        out = ztest @ components
    reference_ms = (time.perf_counter() - start) * 1000.0 / 100.0
    assert out.shape == (ztest.shape[0], expected_k)

    reported = float(data['benchmark_ms'])
    lower = max(1e-6, reference_ms / 100.0)
    upper = reference_ms * 100.0 + 10.0
    assert lower <= reported <= upper, \
        f'Reported benchmark_ms {reported} is implausible; verifier measured about {reference_ms} ms'
    assert reported * 100.0 <= elapsed * 1000.0 * 5.0, \
        'The claimed total benchmark work could not fit in the script execution time'
    return data


def command_for(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return ['python3', str(path)]
    if suffix == '.sh':
        return ['bash', str(path)]
    if suffix == '.pl' and shutil.which('perl'):
        return ['perl', str(path)]
    if suffix == '.rb' and shutil.which('ruby'):
        return ['ruby', str(path)]
    if suffix == '.js' and shutil.which('node'):
        return ['node', str(path)]
    if suffix == '.jar' and shutil.which('java'):
        return ['java', '-jar', str(path)]
    if path.stat().st_mode & stat.S_IXUSR:
        return [str(path)]
    return None


def candidate_scripts():
    excluded = {TRAIN.resolve(), TEST.resolve(), RESULTS.resolve()}
    candidates = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path.resolve() in excluded:
            continue
        cmd = command_for(path)
        if cmd is not None:
            name = path.name.lower()
            priority = 0 if any(word in name for word in ('pca', 'solution', 'main', 'task', 'benchmark')) else 1
            candidates.append((priority, -path.stat().st_mtime, path, cmd))
    candidates.sort(key=lambda item: (item[0], item[1], str(item[2])))
    return [(path, cmd) for _, _, path, cmd in candidates]


def run(cmd):
    if RESULTS.exists():
        RESULTS.unlink()
    started = time.perf_counter()
    proc = subprocess.run(
        cmd,
        cwd=str(HOME),
        env={**os.environ, 'HOME': str(HOME)},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
    )
    elapsed = time.perf_counter() - started
    if proc.returncode != 0:
        raise AssertionError(
            f"Script exited with status {proc.returncode}. stderr: {proc.stderr[-2000:]}"
        )
    return elapsed


assert TRAIN.is_file(), f'Missing {TRAIN}'
assert TEST.is_file(), f'Missing {TEST}'
original_train = np.loadtxt(TRAIN, delimiter=',')
original_test = np.loadtxt(TEST, delimiter=',')
assert original_train.shape == (1000, 50)
assert original_test.shape == (10000, 50)

candidates = candidate_scripts()
assert candidates, 'No runnable script was found under /home/user'

# First exercise the submitted artifact on another same-shaped dataset so a
# script that merely emits constants for the provided CSV files cannot pass.
rng = np.random.default_rng(20250317)
challenge_train = None
challenge_test = None
challenge_expected = None
for latent_dim in (3, 4, 5, 7):
    scales = np.linspace(8.0, 2.0, latent_dim)
    projection = rng.normal(size=(latent_dim, 50))
    tr = (rng.normal(size=(1000, latent_dim)) * scales) @ projection
    te = (rng.normal(size=(10000, latent_dim)) * scales) @ projection
    tr += rng.normal(scale=0.35, size=tr.shape)
    te += rng.normal(scale=0.35, size=te.shape)
    expected = pca_answer(tr, te)
    if expected[0] != 6:
        challenge_train, challenge_test, challenge_expected = tr, te, expected
        break
assert challenge_expected is not None

selected = None
errors = []
try:
    for path, cmd in candidates:
        np.savetxt(TRAIN, challenge_train, delimiter=',')
        np.savetxt(TEST, challenge_test, delimiter=',')
        try:
            elapsed = run(cmd)
            check_result(*challenge_expected, elapsed)
            selected = (path, cmd)
            break
        except Exception as exc:
            errors.append(f'{path}: {exc}')

    assert selected is not None, 'No submitted script produced correct computed results. ' + ' | '.join(errors[-4:])

    # Restore the required inputs, execute the same artifact, and retain its
    # results.json as the final deliverable.
    np.savetxt(TRAIN, original_train, delimiter=',')
    np.savetxt(TEST, original_test, delimiter=',')
    actual_expected = pca_answer(original_train, original_test)
    elapsed = run(selected[1])
    final_data = check_result(*actual_expected, elapsed)

    # Preserve all assertions made by the original verifier.
    assert final_data['k'] == 6, f"Expected k to be 6, got {final_data['k']}"
    assert 0.90 < final_data['variance_explained'] < 0.91, \
        f"Expected variance_explained to be between 0.90 and 0.91, got {final_data['variance_explained']}"
finally:
    # Verification must not leave the supplied datasets modified.
    np.savetxt(TRAIN, original_train, delimiter=',')
    np.savetxt(TEST, original_test, delimiter=',')
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
