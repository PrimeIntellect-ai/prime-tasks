#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

import numpy as np

HOME = Path('/home/user')
TRAIN = Path('/app/train.csv')
TEST = Path('/app/test.csv')
TRUTH = Path('/app/test_labels.csv')
PRED = HOME / 'predictions.csv'
BINARY = Path('/tmp/submission_pipeline')


def read_predictions(path):
    assert path.is_file(), f'Expected predictions file at {path} does not exist.'
    lines = path.read_text().splitlines()
    assert lines, 'Predictions file is empty.'
    values = []
    for i, line in enumerate(lines, 1):
        assert re.fullmatch(r'\s*[+-]?\d+\s*', line), \
            f'Prediction line {i} is not exactly one integer: {line!r}'
        values.append(int(line.strip()))
    return np.asarray(values, dtype=int)


def assert_cv_output(stdout):
    relevant = [line for line in stdout.splitlines()
                if 'accuracy' in line.lower() and
                ('fold' in line.lower() or 'validation' in line.lower())]
    assert relevant, 'The C program did not print a 5-fold validation accuracy.'
    assert any('5' in line for line in relevant), \
        'Validation output does not identify the required 5-fold cross-validation.'
    numbers = []
    for line in relevant:
        numbers.extend(float(x) for x in re.findall(r'(?<![A-Za-z])(?:\d+(?:\.\d*)?|\.\d+)', line))
    assert any(0.0 <= x <= 1.0 or 0.0 <= x <= 100.0 for x in numbers), \
        'Could not parse a valid validation accuracy from program output.'


def compile_submission():
    sources = sorted(HOME.rglob('*.c'))
    assert sources, 'No C source program was found under /home/user.'

    preferred = sorted(sources, key=lambda p: (
        p.name.lower() not in ('pipeline.c', 'knn.c', 'main.c'), str(p)))
    attempts = [sources] + [[p] for p in preferred]
    errors = []
    for group in attempts:
        try:
            if BINARY.exists():
                BINARY.unlink()
            result = subprocess.run(
                ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra',
                 *map(str, group), '-lm', '-o', str(BINARY)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=30)
        except subprocess.TimeoutExpired:
            errors.append('compiler timed out')
            continue
        if result.returncode == 0 and BINARY.is_file():
            return
        errors.append(result.stderr[-1500:])
    raise AssertionError('Could not compile the submitted C program:\n' + '\n'.join(errors))


def run_program():
    if PRED.exists():
        PRED.unlink()
    result = subprocess.run(
        [str(BINARY)], cwd=str(HOME), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert result.returncode == 0, \
        f'C program exited with status {result.returncode}. stderr:\n{result.stderr}'
    assert_cv_output(result.stdout)
    return read_predictions(PRED)


def knn_predict(train_x, train_y, test_x, metric='euclidean', k=5):
    answers = []
    for q in test_x:
        delta = train_x - q
        if metric == 'euclidean':
            distances = np.sum(delta * delta, axis=1)
        else:
            distances = np.sum(np.abs(delta), axis=1)
        nearest = np.argsort(distances, kind='stable')[:k]
        labels, counts = np.unique(train_y[nearest], return_counts=True)
        answers.append(int(labels[counts == counts.max()].min()))
    return np.asarray(answers, dtype=int)


def make_behavioral_data():
    rows = []
    # K=5 case: K=3 predicts 2, while K=5 predicts 1.
    for distance, label in zip([1, 2, 3, 4, 5, 6, 7, 8],
                               [2, 2, 1, 1, 1, 2, 2, 2]):
        rows.append(([float(distance), 0.0, 0.0, 0.0], label))

    # Five nearest votes are 2,2,3,3,4, requiring the smaller tied label 2.
    for distance, label in zip([1, 2, 3, 4, 5, 6, 7, 8],
                               [2, 2, 3, 3, 4, 4, 4, 4]):
        rows.append(([100.0 + float(distance), 0.0, 0.0, 0.0], label))

    # Deterministically find a local case where Euclidean and Manhattan 5-NN differ.
    rng = np.random.default_rng(7319)
    metric_points = metric_labels = None
    for _ in range(10000):
        pts = rng.uniform(-9.0, 9.0, size=(8, 2))
        labels = rng.integers(0, 3, size=8)
        x4 = np.column_stack((pts, np.zeros((8, 2))))
        q4 = np.zeros((1, 4))
        if knn_predict(x4, labels, q4, 'euclidean')[0] != knn_predict(x4, labels, q4, 'manhattan')[0]:
            metric_points, metric_labels = pts, labels
            break
    assert metric_points is not None
    for point, label in zip(metric_points, metric_labels):
        rows.append(([200.0 + float(point[0]), float(point[1]), 0.0, 0.0], int(label)))

    train_x = np.asarray([r[0] for r in rows], dtype=float)
    train_y = np.asarray([r[1] for r in rows], dtype=int)
    test_x = np.asarray([[0.0, 0.0, 0.0, 0.0],
                         [100.0, 0.0, 0.0, 0.0],
                         [200.0, 0.0, 0.0, 0.0]], dtype=float)
    expected = knn_predict(train_x, train_y, test_x, 'euclidean', 5)
    assert expected[0] == 1 and expected[1] == 2
    assert expected[2] != knn_predict(train_x, train_y, test_x, 'manhattan', 5)[2]
    return train_x, train_y, test_x, expected


def test_c_pipeline_and_predictions():
    assert TRUTH.is_file(), f'Expected truth file at {TRUTH} does not exist.'
    expected_truth = np.atleast_1d(np.loadtxt(TRUTH, dtype=int))

    # Preserve the original accuracy assertion on the agent's submitted output.
    submitted = read_predictions(PRED)
    assert len(expected_truth) == len(submitted), \
        f'Length mismatch: expected {len(expected_truth)} predictions, got {len(submitted)}'
    submitted_accuracy = np.mean(expected_truth == submitted)
    assert submitted_accuracy >= 0.85, \
        f'Accuracy {submitted_accuracy:.4f} is below the required threshold of 0.85'

    compile_submission()
    original_train = TRAIN.read_bytes()
    original_test = TEST.read_bytes()
    restored_predictions = PRED.read_bytes()

    try:
        # Execute the compiled C artifact on the real data and retain the original check.
        actual = run_program()
        assert len(expected_truth) == len(actual), \
            f'Length mismatch: expected {len(expected_truth)} predictions, got {len(actual)}'
        accuracy = np.mean(expected_truth == actual)
        assert accuracy >= 0.85, \
            f'Accuracy {accuracy:.4f} is below the required threshold of 0.85'
        restored_predictions = PRED.read_bytes()

        # Exercise K=5, Euclidean distance, and smaller-label tie breaking on derived data.
        train_x, train_y, test_x, expected = make_behavioral_data()
        np.savetxt(TRAIN, np.column_stack((train_x, train_y)), delimiter=',',
                   fmt=['%.10f', '%.10f', '%.10f', '%.10f', '%d'])
        np.savetxt(TEST, test_x, delimiter=',', fmt='%.10f')
        behavioral = run_program()
        assert len(behavioral) == len(expected), \
            f'Behavioral run produced {len(behavioral)} predictions; expected {len(expected)}.'
        assert np.array_equal(behavioral, expected), \
            f'KNN behavioral predictions were {behavioral.tolist()}, expected {expected.tolist()}.'
    finally:
        TRAIN.write_bytes(original_train)
        TEST.write_bytes(original_test)
        PRED.write_bytes(restored_predictions)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
