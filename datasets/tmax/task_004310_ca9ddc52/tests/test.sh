#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/recommender')
RESULT = Path('/home/user/result.txt')
DATA = Path('/home/user/data')

USERS_CSV = '''user_id,department
1,CS
2,Math
3,Physics
4,CS
'''
TRAIN_CSV = '''user_id,paper_id,rating
1,101,5
1,102,
1,103,4
2,101,4
2,102,5
2,103,2
3,101,
3,102,4
3,103,5
4,101,2
4,102,3
4,103,
'''
VAL_CSV = '''user_id,paper_id,rating
1,102,3
3,101,4
4,103,2
'''


def calculate_expected():
    with open(DATA / 'users.csv', newline='') as f:
        users = sorted(int(row['user_id']) for row in csv.DictReader(f))

    rows = []
    valid_by_user = {uid: [] for uid in users}
    with open(DATA / 'train_ratings.csv', newline='') as f:
        for row in csv.DictReader(f):
            uid = int(row['user_id'])
            pid = int(row['paper_id'])
            rating = None if row['rating'] == '' else float(row['rating'])
            rows.append((uid, pid, rating))
            if rating is not None:
                valid_by_user.setdefault(uid, []).append(rating)

    averages = {
        uid: (sum(valid_by_user.get(uid, [])) / len(valid_by_user[uid])
              if valid_by_user.get(uid) else 3.0)
        for uid in users
    }
    matrix = {
        (uid, pid): (averages[uid] if rating is None else rating)
        for uid, pid, rating in rows
    }
    papers = sorted({pid for _, pid, _ in rows})

    vectors = {uid: [matrix[(uid, pid)] for pid in papers] for uid in users}

    def cosine(a, b):
        va, vb = vectors[a], vectors[b]
        dot = sum(x * y for x, y in zip(va, vb))
        na = math.sqrt(sum(x * x for x in va))
        nb = math.sqrt(sum(y * y for y in vb))
        return 0.0 if na == 0.0 or nb == 0.0 else dot / (na * nb)

    similarities = {
        uid: sorted(
            ((cosine(uid, other), other) for other in users if other != uid),
            key=lambda item: (-item[0], item[1]),
        )
        for uid in users
    }

    with open(DATA / 'val_ratings.csv', newline='') as f:
        validation = sorted(
            (int(row['user_id']), int(row['paper_id']), float(row['rating']))
            for row in csv.DictReader(f)
        )

    def predict(uid, pid, k):
        neighbors = [other for _, other in similarities[uid][:k]]
        values = [matrix[(other, pid)] for other in neighbors]
        return sum(values) / len(values)

    mse_by_k = {}
    for k in (1, 2, 3):
        errors = [(predict(uid, pid, k) - actual) ** 2
                  for uid, pid, actual in validation]
        mse_by_k[k] = sum(errors) / len(errors)

    best_k = min((1, 2, 3), key=lambda k: (mse_by_k[k], k))
    predictions = [
        f'{uid},{pid},{predict(uid, pid, best_k):.2f}'
        for uid, pid, _ in validation
    ]
    return best_k, predictions


@pytest.fixture(scope='session', autouse=True)
def build_and_run_submission():
    assert PROJECT.is_dir(), 'Rust project directory /home/user/recommender is missing.'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing from the Rust project.'
    assert any(PROJECT.rglob('*.rs')), 'The project contains no Rust source files.'

    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / 'users.csv').write_text(USERS_CSV)
    (DATA / 'train_ratings.csv').write_text(TRAIN_CSV)
    (DATA / 'val_ratings.csv').write_text(VAL_CSV)
    expected = calculate_expected()

    if RESULT.exists():
        RESULT.unlink()

    try:
        proc = subprocess.run(
            ['cargo', 'run', '--quiet'],
            cwd=PROJECT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('cargo run timed out after 120 seconds.')

    assert proc.returncode == 0, (
        'The Rust project failed to compile or run.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    return expected


def test_result_file_exists(build_and_run_submission):
    assert RESULT.is_file(), (
        'File /home/user/result.txt is missing. '
        'Did the Rust program run and generate the output?'
    )


def test_result_content(build_and_run_submission):
    expected_k, expected_predictions = build_and_run_submission
    if not RESULT.is_file():
        pytest.fail('File /home/user/result.txt is missing.')

    with RESULT.open() as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 2, 'Result file does not contain enough lines.'

    best_k_line = lines[0]
    assert best_k_line.startswith('Best K:'), (
        f"Expected first line to start with 'Best K:', got '{best_k_line}'"
    )
    try:
        k_val = int(best_k_line.split(':', 1)[1].strip())
    except (ValueError, IndexError):
        pytest.fail(f'Could not parse K from line: {best_k_line}')

    assert k_val == expected_k, f'Expected Best K to be {expected_k}, but got {k_val}'
    assert lines[1] == 'Predictions:', (
        f"Expected second line to be 'Predictions:', got '{lines[1]}'"
    )

    actual_predictions = lines[2:]
    assert len(actual_predictions) == len(expected_predictions), (
        f'Expected {len(expected_predictions)} predictions, '
        f'but got {len(actual_predictions)}'
    )
    for expected, actual in zip(expected_predictions, actual_predictions):
        assert actual == expected, f"Expected prediction '{expected}', but got '{actual}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
