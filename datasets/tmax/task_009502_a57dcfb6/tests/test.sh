#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import py_compile
import stat
import subprocess
from pathlib import Path

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

SCRIPT = Path('/home/user/organize.py')
DATASET = Path('/home/user/dataset.jsonl')
OUTPUT = Path('/home/user/duplicates.json')

ORIGINAL = [
    {'id': 1, 'text': 'The quick brown fox jumps over the lazy dog.', 'split': 'train'},
    {'id': 2, 'text': 'Data science is an interdisciplinary field that uses scientific methods.', 'split': 'train'},
    {'id': 3, 'text': 'Bayesian inference is a method of statistical inference.', 'split': 'train'},
    {'id': 4, 'text': 'Python is a high-level, general-purpose programming language.', 'split': 'train'},
    {'id': 5, 'text': 'The quick brown fox jumps over the lazy dog.', 'split': 'test'},
    {'id': 6, 'text': 'Data science is interdisciplinary and uses scientific methods.', 'split': 'test'},
    {'id': 7, 'text': 'I love eating pizza with pineapple.', 'split': 'test'},
    {'id': 8, 'text': 'A totally unrelated text about space exploration.', 'split': 'test'},
    {'id': 9, 'text': 'Python is a high-level, general-purpose programming language.', 'split': 'test'},
]


def write_dataset(rows):
    DATASET.write_text(''.join(json.dumps(row) + '\n' for row in rows), encoding='utf-8')


def execute(rows):
    write_dataset(rows)
    if OUTPUT.exists():
        OUTPUT.unlink()
    completed = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'organize.py exited with {completed.returncode}\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert OUTPUT.exists(), f'Output file missing at {OUTPUT}'
    try:
        with OUTPUT.open('r', encoding='utf-8') as f:
            result = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {OUTPUT} is not valid JSON: {exc}')
    assert isinstance(result, list), f'Expected a JSON array, got {type(result)}'
    return result


def reference(rows):
    train = [row for row in rows if row['split'] == 'train']
    test = [row for row in rows if row['split'] == 'test']
    vectorizer = TfidfVectorizer()
    train_vectors = vectorizer.fit_transform([row['text'] for row in train])
    test_vectors = vectorizer.transform([row['text'] for row in test])
    similarities = cosine_similarity(test_vectors, train_vectors)

    high_prob = round((0.85 * 0.05) / (0.85 * 0.05 + 0.02 * 0.95), 4)
    low_prob = round((0.15 * 0.05) / (0.15 * 0.05 + 0.98 * 0.95), 4)
    expected = []
    for test_index, test_row in enumerate(test):
        for train_index, train_row in enumerate(train):
            prob = high_prob if similarities[test_index, train_index] >= 0.7 else low_prob
            if prob > 0.5:
                expected.append({
                    'test_id': test_row['id'],
                    'train_id': train_row['id'],
                    'prob': prob,
                })
    return sorted(expected, key=lambda item: (-item['prob'], item['test_id'], item['train_id']))


def assert_exact_result(actual, expected):
    for index, item in enumerate(actual):
        assert isinstance(item, dict), f'Result {index} is not an object'
        assert set(item) == {'test_id', 'train_id', 'prob'}, f'Unexpected fields in result {index}: {item}'
        assert type(item['test_id']) is int, f'test_id in result {index} must be an int'
        assert type(item['train_id']) is int, f'train_id in result {index} must be an int'
        assert type(item['prob']) in (int, float), f'prob in result {index} must be numeric'
    assert actual == expected, f'Expected {expected}, got {actual}'


def assert_original_checks(results):
    # Preserve the original verifier's assertions.
    expected_prob = round((0.85 * 0.05) / (0.85 * 0.05 + 0.02 * 0.95), 4)
    expected_pairs = [(5, 1), (6, 2), (9, 4)]
    assert len(results) == len(expected_pairs), f'Expected {len(expected_pairs)} duplicate pairs, got {len(results)}'
    for i, res in enumerate(results):
        assert 'test_id' in res, f"Missing 'test_id' in result {i}"
        assert 'train_id' in res, f"Missing 'train_id' in result {i}"
        assert 'prob' in res, f"Missing 'prob' in result {i}"
        assert res['prob'] == expected_prob, f"Expected prob {expected_prob} for pair, got {res['prob']}"
    actual_pairs = [(res['test_id'], res['train_id']) for res in results]
    expected_sorted_pairs = sorted(expected_pairs)
    assert actual_pairs == expected_sorted_pairs, f'Expected pairs {expected_sorted_pairs} (properly sorted), got {actual_pairs}'


def test_script_and_outputs():
    assert SCRIPT.exists(), f'Required script missing at {SCRIPT}'
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), f'{SCRIPT} must be a regular file'
    assert SCRIPT.stat().st_size > 0, f'{SCRIPT} is empty'
    py_compile.compile(str(SCRIPT), doraise=True)

    leakage_case = [
        {'id': 410, 'text': 'alpha bravo charlie delta', 'split': 'train'},
    ] + [
        {'id': 700 + i, 'text': f'alpha bravo noise{i:02d}', 'split': 'test'}
        for i in range(12)
    ]

    all_pairs_case = [
        {'id': 90, 'text': 'orchid tulip cedar', 'split': 'train'},
        {'id': 12, 'text': 'orchid tulip cedar', 'split': 'train'},
        {'id': 44, 'text': 'planet comet galaxy', 'split': 'train'},
        {'id': 205, 'text': 'orchid tulip cedar', 'split': 'test'},
        {'id': 103, 'text': 'planet comet galaxy', 'split': 'test'},
        {'id': 307, 'text': 'unrelated cooking recipe', 'split': 'test'},
    ]

    try:
        original_result = execute(ORIGINAL)
        assert_original_checks(original_result)

        # Unknown test-only terms are ignored only when TF-IDF is fitted on train.
        leakage_result = execute(leakage_case)
        assert_exact_result(leakage_result, reference(leakage_case))

        # Require every qualifying test/train pair and the specified ordering.
        all_pairs_result = execute(all_pairs_case)
        assert_exact_result(all_pairs_result, reference(all_pairs_case))
    finally:
        # Leave the requested output generated from the original dataset.
        write_dataset(ORIGINAL)
        subprocess.run(
            ['python3', str(SCRIPT)],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )

    final_result = json.loads(OUTPUT.read_text(encoding='utf-8'))
    assert_original_checks(final_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
