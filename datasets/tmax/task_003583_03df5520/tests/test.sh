#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.linear_model import Ridge
from sklearn.model_selection import KFold, cross_val_score
from sklearn.utils import resample

FEATURES_PATH = Path('/home/user/features.csv')
TARGETS_PATH = Path('/home/user/targets.csv')
RESULTS_PATH = Path('/home/user/bootstrap_results.txt')


def expected_result(features, targets):
    joined = pd.merge(features, targets, on='sample_id')
    X = joined[['f1', 'f2', 'f3']]
    y = joined['target']
    alphas = [0.1, 1.0, 10.0]

    alpha_mses = []
    for alpha in alphas:
        cv = KFold(n_splits=5, shuffle=True, random_state=42)
        scores = cross_val_score(
            Ridge(alpha=alpha), X, y, cv=cv,
            scoring='neg_mean_squared_error'
        )
        alpha_mses.append(-scores.mean())

    best_alpha = alphas[int(np.argmin(alpha_mses))]
    bootstrap_mses = []
    for i in range(100):
        sample = resample(joined, random_state=i)
        sample_X = sample[['f1', 'f2', 'f3']]
        sample_y = sample['target']
        cv = KFold(n_splits=5, shuffle=True, random_state=42)
        scores = cross_val_score(
            Ridge(alpha=best_alpha), sample_X, sample_y, cv=cv,
            scoring='neg_mean_squared_error'
        )
        bootstrap_mses.append(-scores.mean())

    low, high = np.percentile(bootstrap_mses, [5, 95])
    return [
        f'Best Alpha: {best_alpha}',
        f'5th Percentile: {low:.4f}',
        f'95th Percentile: {high:.4f}',
    ]


def make_case(seed, n, scale):
    rng = np.random.default_rng(seed)
    X = rng.normal(size=(n, 3))
    y = (1.7 * X[:, 0] - 0.8 * X[:, 1] + 0.25 * X[:, 2]
         + rng.normal(scale=scale, size=n))
    ids = rng.permutation(np.arange(10000, 10000 + n))
    features = pd.DataFrame({
        'sample_id': ids,
        'f1': X[:, 0],
        'f2': X[:, 1],
        'f3': X[:, 2],
    }).sample(frac=1, random_state=seed).reset_index(drop=True)
    targets = pd.DataFrame({
        'sample_id': ids,
        'target': y,
    }).sample(frac=1, random_state=seed + 1).reset_index(drop=True)
    return features, targets


def read_result_lines():
    assert RESULTS_PATH.is_file(), f'File {RESULTS_PATH} is missing.'
    with RESULTS_PATH.open('r') as f:
        return [line.strip() for line in f.read().strip().split('\n') if line.strip()]


def test_bootstrap_results_exists_and_correct():
    file_path = '/home/user/bootstrap_results.txt'
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected_lines = [
        "Best Alpha: 1.0",
        "5th Percentile: 0.1557",
        "95th Percentile: 0.3661"
    ]

    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]

    assert len(actual_lines) == 3, f"Expected 3 lines in {file_path}, but got {len(actual_lines)}."
    assert actual_lines[0] == expected_lines[0], f"Expected line 1 to be '{expected_lines[0]}', got '{actual_lines[0]}'."
    assert actual_lines[1] == expected_lines[1], f"Expected line 2 to be '{expected_lines[1]}', got '{actual_lines[1]}'."
    assert actual_lines[2] == expected_lines[2], f"Expected line 3 to be '{expected_lines[2]}', got '{actual_lines[2]}'."

    candidates = []
    for path in Path('/home/user').rglob('*.py'):
        try:
            mode = path.lstat().st_mode
            if stat.S_ISREG(mode) and not path.is_symlink():
                candidates.append(path)
        except OSError:
            pass
    assert candidates, 'No Python analysis script was created under /home/user.'

    original_features = FEATURES_PATH.read_bytes()
    original_targets = TARGETS_PATH.read_bytes()
    original_results = RESULTS_PATH.read_bytes()

    random_seed = secrets.randbits(31)
    cases = [
        make_case(random_seed, 67, 0.35),
        make_case(random_seed + 9173, 83, 1.10),
    ]
    expected_cases = [expected_result(f, t) for f, t in cases]

    errors = []
    passed_script = None
    try:
        for candidate in sorted(candidates):
            candidate_ok = True
            for (features, targets), expected in zip(cases, expected_cases):
                features.to_csv(FEATURES_PATH, index=False)
                targets.to_csv(TARGETS_PATH, index=False)
                if RESULTS_PATH.exists():
                    RESULTS_PATH.unlink()
                try:
                    proc = subprocess.run(
                        ['python3', str(candidate)],
                        cwd='/home/user',
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=120,
                    )
                except Exception as exc:
                    errors.append(f'{candidate}: could not execute: {exc}')
                    candidate_ok = False
                    break
                if proc.returncode != 0:
                    errors.append(f'{candidate}: exited with {proc.returncode}: {proc.stderr[-500:]}')
                    candidate_ok = False
                    break
                try:
                    got = read_result_lines()
                except AssertionError as exc:
                    errors.append(f'{candidate}: {exc}')
                    candidate_ok = False
                    break
                if got != expected:
                    errors.append(f'{candidate}: expected {expected}, got {got}')
                    candidate_ok = False
                    break
            if candidate_ok:
                passed_script = candidate
                break
    finally:
        FEATURES_PATH.write_bytes(original_features)
        TARGETS_PATH.write_bytes(original_targets)
        RESULTS_PATH.write_bytes(original_results)

    assert passed_script is not None, (
        'No created Python script correctly performed the join, alpha selection, '
        'cross-validation, and bootstrap calculation on independent inputs. '
        + ' | '.join(errors[-5:])
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
