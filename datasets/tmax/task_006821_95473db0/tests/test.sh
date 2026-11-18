#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sys
import uuid
import random
import subprocess
from pathlib import Path

import pandas as pd
from pandas.testing import assert_frame_equal
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import RidgeClassifier
from sklearn.model_selection import GridSearchCV

HOME = Path('/home/user')
INPUT = HOME / 'papers.csv'
PARQUET = HOME / 'processed_papers.parquet'
ALPHA = HOME / 'best_alpha.txt'
METRICS = HOME / 'metrics.txt'


def find_submission_script():
    candidates = []
    for path in HOME.rglob('*.py'):
        if not path.is_file():
            continue
        try:
            source = path.read_text(encoding='utf-8')
        except (OSError, UnicodeDecodeError):
            continue
        required_paths = ('papers.csv', 'processed_papers.parquet', 'best_alpha.txt', 'metrics.txt')
        required_tools = ('TfidfVectorizer', 'GridSearchCV', 'RidgeClassifier')
        if all(value in source for value in required_paths + required_tools):
            candidates.append(path)

    assert candidates, 'No self-contained Python submission script implementing the requested pipeline was found.'
    candidates.sort(key=lambda p: (len(p.parts), str(p)))
    return candidates[0]


def run_submission(script):
    for path in (PARQUET, ALPHA, METRICS):
        if path.exists():
            path.unlink()
    result = subprocess.run(
        [sys.executable, str(script)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'Submission script failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def derive_expected(input_frame):
    expected = input_frame[input_frame['year'] >= 2010].copy()
    vectorizer = TfidfVectorizer(max_features=50, stop_words='english')
    embeddings = vectorizer.fit_transform(expected['title'])
    search = GridSearchCV(
        RidgeClassifier(random_state=42),
        {'alpha': [0.1, 1.0, 10.0]},
        cv=3,
    )
    search.fit(embeddings, expected['category'])
    expected['predicted_category'] = search.best_estimator_.predict(embeddings)

    lengths = expected['title'].str.len().groupby(expected['predicted_category']).mean()
    expected_metrics = [
        f'Category: {category}, Avg_Length: {lengths[category]:.2f}'
        for category in sorted(lengths.index)
    ]
    return expected, str(search.best_params_['alpha']), expected_metrics


def assert_semantic_outputs(input_frame):
    assert PARQUET.is_file(), f'File not found: {PARQUET}'
    try:
        actual = pd.read_parquet(PARQUET)
    except Exception as exc:
        raise AssertionError(f'{PARQUET} is not a readable Parquet dataset: {exc}') from exc

    expected, expected_alpha, expected_metrics = derive_expected(input_frame)
    assert list(actual.columns) == list(expected.columns), (
        f'Parquet columns differ: expected {list(expected.columns)}, got {list(actual.columns)}'
    )
    assert_frame_equal(
        actual.reset_index(drop=True),
        expected.reset_index(drop=True),
        check_dtype=False,
        check_like=False,
    )

    assert ALPHA.is_file(), f'File not found: {ALPHA}'
    assert ALPHA.read_text().strip() == expected_alpha

    assert METRICS.is_file(), f'File not found: {METRICS}'
    actual_metrics = [line.strip() for line in METRICS.read_text().splitlines() if line.strip()]
    assert actual_metrics == expected_metrics, (
        f'Metrics differ: expected {expected_metrics}, got {actual_metrics}'
    )


# Original assertions retained.
def test_parquet_file_exists_and_valid():
    file_path = '/home/user/processed_papers.parquet'
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, 'rb') as f:
        header = f.read(4)
        f.seek(-4, os.SEEK_END)
        footer = f.read(4)

    assert header == b'PAR1', f"File {file_path} does not have a valid Parquet header."
    assert footer == b'PAR1', f"File {file_path} does not have a valid Parquet footer."


def test_best_alpha():
    file_path = '/home/user/best_alpha.txt'
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == '1.0', f"Expected best alpha to be '1.0', got '{content}'"


def test_metrics():
    file_path = '/home/user/metrics.txt'
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in metrics.txt, got {len(lines)}"

    expected_categories = ['math.AG', 'math.CO', 'math.PR']
    pattern = re.compile(r"^Category: (math\.(?:AG|CO|PR)), Avg_Length: (\d+\.\d{2})$")

    actual_categories = []
    for line in lines:
        match = pattern.match(line)
        assert match, f"Line format incorrect: '{line}'. Expected 'Category: {{category}}, Avg_Length: {{avg_length:.2f}}'"
        actual_categories.append(match.group(1))

    assert actual_categories == expected_categories, f"Categories not sorted alphabetically or missing. Expected {expected_categories}, got {actual_categories}"

    expected_lines = [
        "Category: math.AG, Avg_Length: 30.60",
        "Category: math.CO, Avg_Length: 29.86",
        "Category: math.PR, Avg_Length: 32.75"
    ]

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'"


def make_probe_frame():
    nonce = uuid.uuid4().hex
    rows = []
    labels = [
        ('math.AG', 'algebraic geometry schemes varieties'),
        ('math.CO', 'combinatorial graphs vertices coloring'),
        ('math.PR', 'probability stochastic random martingales'),
    ]
    next_id = 7000
    for category, signal in labels:
        for i in range(6):
            noise = ' '.join(f'noise{nonce}{i}{j}' for j in range(12))
            rows.append({
                'id': next_id,
                'title': f'the {signal} and {noise}',
                'year': 2010 + ((i * 3 + len(category)) % 14),
                'category': category,
            })
            next_id += 1

    for category, signal in labels:
        rows.append({
            'id': next_id,
            'title': f'excluded old {signal} {nonce}',
            'year': 2001,
            'category': category,
        })
        next_id += 1

    random.SystemRandom().shuffle(rows)
    return pd.DataFrame(rows, columns=['id', 'title', 'year', 'category'])


def test_executed_pipeline_and_real_outputs():
    script = find_submission_script()
    original_bytes = INPUT.read_bytes()
    original_frame = pd.read_csv(INPUT)

    try:
        run_submission(script)
        test_parquet_file_exists_and_valid()
        test_best_alpha()
        test_metrics()
        assert_semantic_outputs(original_frame)

        probe = make_probe_frame()
        probe.to_csv(INPUT, index=False)
        run_submission(script)
        assert_semantic_outputs(probe)
    finally:
        INPUT.write_bytes(original_bytes)
        run_submission(script)


if __name__ == '__main__':
    test_executed_pipeline_and_real_outputs()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
