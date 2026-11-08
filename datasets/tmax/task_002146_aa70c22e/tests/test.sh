#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

import numpy as np

HOME = Path('/home/user')
DATA = HOME / 'sensor_data.csv'
SOURCE = HOME / 'pipeline.c'
RUNNER = HOME / 'run.sh'
BEST = HOME / 'best_k.txt'
CLEANED = HOME / 'cleaned_data.csv'
CANDIDATES = [2, 3, 4, 5, 6, 8, 10, 12, 15, 20]


def load_data(path=DATA):
    data = np.loadtxt(path, delimiter=',')
    assert data.shape == (200, 121)
    return data[:, :120], data[:, 120].astype(int)


def reduced(X, k):
    return X.reshape(X.shape[0], 120 // k, k).mean(axis=2)


def correct_count(X, y, k):
    Z = reduced(X, k)
    norms = np.sum(Z * Z, axis=1)
    distances = norms[:, None] + norms[None, :] - 2.0 * Z.dot(Z.T)
    np.fill_diagonal(distances, np.inf)
    predicted = y[np.argmin(distances, axis=1)]
    return int(np.sum(predicted == y))


def expected_best(X, y):
    scores = {k: correct_count(X, y, k) for k in CANDIDATES}
    maximum = max(scores.values())
    return max(k for k in CANDIDATES if scores[k] == maximum), scores


def expected_cleaned_lines(X, y, k):
    Z = reduced(X, k)
    return [','.join([*(f'{value:.4f}' for value in row), str(int(label))])
            for row, label in zip(Z, y)]


def run_orchestration():
    subprocess.run([str(RUNNER)], cwd=HOME, check=True, timeout=180,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def assert_outputs(X, y, expected_k):
    assert BEST.is_file(), f'File {BEST} does not exist.'
    content = BEST.read_text().strip()
    assert content == str(expected_k), (
        f'Expected best_k.txt to contain {expected_k!r}, but got {content!r}.'
    )

    assert CLEANED.is_file(), f'Output file {CLEANED} is missing.'
    expected = expected_cleaned_lines(X, y, expected_k)
    actual = CLEANED.read_text().strip().splitlines()
    assert len(actual) == len(expected), (
        f'Expected {len(expected)} rows in cleaned_data.csv, but found {len(actual)}.'
    )
    for index, (got, wanted) in enumerate(zip(actual, expected), 1):
        assert got.strip() == wanted, (
            f'Mismatch at row {index} in cleaned_data.csv.\n'
            f'Expected: {wanted}\nGot:      {got.strip()}'
        )


def numeric_accuracy_values(text):
    values = []
    number = r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?'
    for line in text.splitlines():
        stripped = line.strip()
        match = re.fullmatch(rf'({number})\s*(%)?', stripped)
        if match:
            value = float(match.group(1))
            values.append(value / 100.0 if match.group(2) else value)
        elif 'acc' in stripped.lower() or 'loocv' in stripped.lower():
            for token, percent in re.findall(rf'({number})\s*(%)?', stripped):
                value = float(token)
                values.append(value / 100.0 if percent else value)
    return values


def assert_c_accuracies(binary, scores):
    for k in CANDIDATES:
        result = subprocess.run([str(binary), str(k)], cwd=HOME, timeout=60,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True)
        assert result.returncode == 0, (
            f'Compiled pipeline failed for k={k}. stderr: {result.stderr}'
        )
        values = numeric_accuracy_values(result.stdout)
        expected = scores[k] / 200.0
        assert any(abs(value - expected) < 1e-6 for value in values), (
            f'pipeline.c did not report the correct LOOCV accuracy for k={k}. '
            f'Expected {expected} (or {expected * 100}%), stdout was: '
            f'{result.stdout!r}'
        )


def make_unpredictable_fixture_with_non8_optimum():
    seed = int.from_bytes(secrets.token_bytes(8), 'little')
    for offset in range(64):
        rng = np.random.default_rng(seed + offset)
        X = rng.normal(size=(200, 120))
        y = rng.integers(0, 2, size=200)
        np.savetxt(DATA, np.column_stack((X, y)), delimiter=',', fmt='%.6f')
        X_saved, y_saved = load_data()
        best, scores = expected_best(X_saved, y_saved)
        if best != 8:
            return X_saved, y_saved, best, scores
    raise AssertionError('Could not construct a validation fixture with an optimum other than 8')


def test_complete_c_tuning_pipeline():
    assert SOURCE.is_file() and not SOURCE.is_symlink(), (
        '/home/user/pipeline.c must be a regular C source file.'
    )
    assert RUNNER.is_file() and not RUNNER.is_symlink(), (
        '/home/user/run.sh must be a regular file.'
    )
    assert os.access(RUNNER, os.X_OK), '/home/user/run.sh is not executable.'

    original_bytes = DATA.read_bytes()
    original_X, original_y = load_data()

    binary = Path('/tmp/submitted_pipeline')
    compile_result = subprocess.run(
        ['gcc', '-O2', str(SOURCE), '-o', str(binary), '-lm'],
        cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert compile_result.returncode == 0, (
        f'pipeline.c does not compile with gcc: {compile_result.stderr}'
    )

    try:
        # Execute the submitted orchestration on the required fixture first.
        run_orchestration()
        assert BEST.read_text().strip() == '8', (
            f"Expected best_k.txt to contain '8', but got {BEST.read_text().strip()!r}."
        )
        assert_outputs(original_X, original_y, 8)

        # Replace only the data temporarily with an unpredictable valid 200x120
        # fixture. This prevents a hardcoded k=8 pipeline from passing.
        X, y, best, scores = make_unpredictable_fixture_with_non8_optimum()

        # Exercise the independently compiled C artifact for every required k.
        assert_c_accuracies(binary, scores)

        # Exercise run.sh and verify that it tunes rather than hardcoding k=8.
        run_orchestration()
        assert_outputs(X, y, best)
    finally:
        DATA.write_bytes(original_bytes)

    # Leave and verify the final artifacts for the original required dataset.
    run_orchestration()
    assert BEST.read_text().strip() == '8', (
        f"Expected best_k.txt to contain '8', but got {BEST.read_text().strip()!r}."
    )
    assert_outputs(original_X, original_y, 8)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
