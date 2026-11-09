#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_pipeline.py
import csv
import json
import math
import os
import secrets
import stat
import string
import subprocess
from pathlib import Path

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

PRODUCTS = Path('/home/user/products.csv')
OUTPUT = Path('/home/user/recommendations.json')


def load_json():
    assert OUTPUT.is_file(), f'File {OUTPUT} is missing. The pipeline did not save the output correctly.'
    try:
        with OUTPUT.open('r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{OUTPUT} is not a valid JSON file.') from exc


def check_original_output():
    data = load_json()
    assert isinstance(data, list), f'Expected the JSON file to contain a list, but got {type(data).__name__}.'
    assert len(data) == 3, f'Expected exactly 3 recommendations, but found {len(data)}.'

    expected_results = [
        {'id': 'train_3', 'score': 0.3846},
        {'id': 'train_1', 'score': 0.2640},
        {'id': 'train_5', 'score': 0.1659},
    ]

    for i, (actual, expected) in enumerate(zip(data, expected_results)):
        assert isinstance(actual, dict), f'Item at index {i} is not a dictionary.'
        assert 'id' in actual, f"Item at index {i} is missing the 'id' key."
        assert 'score' in actual, f"Item at index {i} is missing the 'score' key."
        assert actual['id'] == expected['id'], (
            f"Expected id '{expected['id']}' at rank {i + 1}, but got '{actual['id']}'."
        )
        try:
            actual_score = float(actual['score'])
        except (ValueError, TypeError) as exc:
            raise AssertionError(
                f"Score for item '{actual['id']}' is not a valid number: {actual['score']}"
            ) from exc
        assert math.isclose(actual_score, expected['score'], abs_tol=0.0002), (
            f"Expected score {expected['score']} for id '{expected['id']}', but got {actual_score}."
        )


def token():
    return ''.join(secrets.choice(string.ascii_lowercase) for _ in range(14))


def make_hidden_dataset():
    # Generate a fresh corpus for which fitting on all rows gives observably
    # different answers from fitting only on the training descriptions.
    for _ in range(200):
        vocab = [token() for _ in range(14)]
        rows = []
        train_ids = ['train_' + token() for _ in range(7)]
        train_docs = []
        for item_id in train_ids:
            chosen = secrets.SystemRandom().sample(vocab, secrets.randbelow(5) + 3)
            doc = ' '.join(chosen)
            train_docs.append(doc)
            rows.append({'id': item_id, 'split': 'train', 'description': doc})

        target_words = secrets.SystemRandom().sample(vocab, 6)
        target_doc = ' '.join(target_words)
        poison_words = secrets.SystemRandom().sample(vocab, 7)
        poison_doc = ' '.join(poison_words + poison_words[:3])
        rows.extend([
            {'id': 'test_1', 'split': 'test', 'description': target_doc},
            {'id': 'test_' + token(), 'split': 'test', 'description': poison_doc},
        ])

        vec = TfidfVectorizer(stop_words='english', lowercase=True)
        train_matrix = vec.fit_transform(train_docs)
        target_matrix = vec.transform([target_doc])
        scores = cosine_similarity(target_matrix, train_matrix)[0]
        order = np.argsort(-scores, kind='stable')[:3]
        expected = [(train_ids[i], round(float(scores[i]), 4)) for i in order]

        all_docs = train_docs + [target_doc, poison_doc]
        leaky_vec = TfidfVectorizer(stop_words='english', lowercase=True)
        leaky_matrix = leaky_vec.fit_transform(all_docs)
        leaky_scores = cosine_similarity(leaky_matrix[-2], leaky_matrix[:len(train_docs)])[0]
        leaky_order = np.argsort(-leaky_scores, kind='stable')[:3]
        leaky = [(train_ids[i], round(float(leaky_scores[i]), 4)) for i in leaky_order]

        top_scores = [scores[i] for i in order]
        no_ties = all(abs(float(top_scores[i] - top_scores[i + 1])) > 0.002 for i in range(2))
        if no_ties and expected != leaky and expected[-1][1] > 0:
            return rows, expected
    raise AssertionError('Could not construct a suitable hidden test corpus.')


def candidate_artifacts():
    candidates = []
    seen = set()
    roots = [Path('/home/user'), Path('/tmp'), Path('/root'), Path('/workspace')]
    excluded = {PRODUCTS.resolve(), OUTPUT.resolve(), Path('/tmp/verify_pipeline.py').resolve()}

    for root_index, root in enumerate(roots):
        if not root.exists():
            continue
        try:
            paths = root.rglob('*')
            for path in paths:
                try:
                    if not path.is_file() or path.resolve() in excluded:
                        continue
                    relative_parts = path.relative_to(root).parts
                    if any(part.startswith('.') for part in relative_parts):
                        continue
                    info = path.stat()
                    if info.st_size == 0 or info.st_size > 2_000_000:
                        continue
                    executable = bool(info.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
                    if path.suffix.lower() not in {'.py', '.sh'} and not executable:
                        continue
                    resolved = str(path.resolve())
                    if resolved in seen:
                        continue
                    seen.add(resolved)
                    try:
                        body = path.read_bytes()
                    except OSError:
                        body = b''
                    mentions_paths = b'products.csv' in body and b'recommendations.json' in body
                    # Home-directory artifacts are preferred; outside artifacts
                    # must identify both required files to avoid running unrelated scripts.
                    if root != Path('/home/user') and not mentions_paths:
                        continue
                    candidates.append((root_index, not mentions_paths, -info.st_mtime, path))
                except (OSError, ValueError):
                    continue
        except OSError:
            continue

    candidates.sort(key=lambda item: item[:3])
    return [item[3] for item in candidates]


def command_for(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return ['python3', str(path)]
    if suffix == '.sh':
        return ['bash', str(path)]
    return [str(path)]


def check_hidden_output(expected):
    data = load_json()
    assert isinstance(data, list) and len(data) == 3
    for actual, (expected_id, expected_score) in zip(data, expected):
        assert isinstance(actual, dict)
        assert set(actual.keys()) == {'id', 'score'}
        assert actual['id'] == expected_id
        assert not isinstance(actual['score'], bool)
        actual_score = float(actual['score'])
        assert math.isfinite(actual_score)
        assert math.isclose(actual_score, expected_score, abs_tol=0.0002)


def main():
    check_original_output()
    original_products = PRODUCTS.read_bytes()
    original_output = OUTPUT.read_bytes()
    candidates = candidate_artifacts()
    assert candidates, 'No runnable recommendation pipeline artifact was found.'

    rows, expected = make_hidden_dataset()
    try:
        for artifact in candidates:
            with PRODUCTS.open('w', encoding='utf-8', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=['id', 'split', 'description'])
                writer.writeheader()
                writer.writerows(rows)
            try:
                OUTPUT.unlink()
            except FileNotFoundError:
                pass

            try:
                result = subprocess.run(
                    command_for(artifact),
                    cwd='/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=30,
                    check=False,
                    env=os.environ.copy(),
                )
            except (OSError, subprocess.TimeoutExpired):
                continue

            if result.returncode != 0 or not OUTPUT.is_file():
                continue
            try:
                check_hidden_output(expected)
                return
            except (AssertionError, ValueError, TypeError, json.JSONDecodeError):
                continue

        raise AssertionError(
            'No submitted pipeline produced correct recommendations on a hidden corpus using training-only TF-IDF fitting.'
        )
    finally:
        PRODUCTS.write_bytes(original_products)
        OUTPUT.write_bytes(original_output)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
