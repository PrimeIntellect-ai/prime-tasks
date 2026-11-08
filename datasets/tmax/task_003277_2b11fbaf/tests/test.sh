#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

SOURCE_PATH = '/home/user/dataset.csv'
JSON_PATH = '/home/user/duplicate_pairs.json'
CLEANED_PATH = '/home/user/cleaned_dataset.csv'

EXPECTED_SOURCE = [
    (1, 'Doc A', 'The quick brown fox jumps over the lazy dog.'),
    (2, 'Doc B', 'Machine learning is fascinating and drives modern AI.'),
    (3, 'Doc C', 'The quick brown fox jumped over the lazy dog.'),
    (4, 'Doc D', 'Data science involves statistics, coding, and domain knowledge.'),
    (5, 'Doc E', 'Cloud computing provides scalable resources on demand.'),
    (6, 'Doc F', 'Artificial intelligence and machine learning are fascinating.'),
    (7, 'Doc G', 'Cybersecurity is crucial for protecting sensitive data.'),
    (8, 'Doc H', 'Data science needs statistics, coding, and domain expertise.'),
    (9, 'Doc I', 'Software engineering practices ensure code quality.'),
    (10, 'Doc J', 'Quantum computing uses quantum bits or qubits.'),
]


def compute_reference():
    assert os.path.isfile(SOURCE_PATH), f'Missing {SOURCE_PATH}'
    source = pd.read_csv(SOURCE_PATH)
    assert list(source.columns) == ['doc_id', 'title', 'text'], 'Source dataset columns were modified.'

    actual_source = [
        (int(row.doc_id), str(row.title), str(row.text))
        for row in source.itertuples(index=False)
    ]
    assert actual_source == EXPECTED_SOURCE, 'The source dataset was modified.'

    tfidf = TfidfVectorizer().fit_transform(source['text'])
    similarities = cosine_similarity(tfidf)

    candidates = []
    for i in range(len(source)):
        for j in range(i + 1, len(source)):
            first = int(source.iloc[i]['doc_id'])
            second = int(source.iloc[j]['doc_id'])
            pair = [min(first, second), max(first, second)]
            candidates.append((float(similarities[i, j]), i, j, pair))

    candidates.sort(key=lambda item: (-item[0], item[1], item[2]))
    expected_pairs = [item[3] for item in candidates[:3]]
    dropped_ids = {pair[1] for pair in expected_pairs}

    keep_positions = [
        i for i, doc_id in enumerate(source['doc_id'])
        if int(doc_id) not in dropped_ids
    ]
    cleaned = source.iloc[keep_positions].copy()
    coordinates = TruncatedSVD(n_components=2, random_state=42).fit_transform(
        tfidf[keep_positions]
    )

    expected_rows = {}
    for position, row in enumerate(cleaned.itertuples(index=False)):
        expected_rows[int(row.doc_id)] = {
            'title': str(row.title),
            'text': str(row.text),
            'pca': coordinates[position],
        }

    return expected_pairs, expected_rows


def test_duplicate_pairs_json():
    """Verify the JSON structure, exact computed pairs, and similarity order."""
    expected_pairs, _ = compute_reference()

    assert os.path.isfile(JSON_PATH), f'Missing {JSON_PATH}'
    with open(JSON_PATH, 'r') as f:
        try:
            pairs = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {JSON_PATH} is not valid JSON.')

    assert isinstance(pairs, list), 'JSON root must be a list.'
    assert len(pairs) == 3, f'Expected 3 duplicate pairs, found {len(pairs)}.'

    fixed_expected_pairs = [[1, 3], [4, 8], [2, 6]]

    for p in pairs:
        assert isinstance(p, list) and len(p) == 2, 'Each pair must be a list of 2 integers.'
        assert type(p[0]) is int and type(p[1]) is int, f'Pair entries must be integers: {p}'
        assert p[0] < p[1], f'Pair {p} is not sorted (smaller ID must come first).'

    sorted_expected = sorted(fixed_expected_pairs)
    sorted_actual = sorted(pairs)
    assert sorted_actual == sorted_expected, f'Expected pairs {sorted_expected}, got {sorted_actual}'

    assert pairs == expected_pairs, (
        f'Pairs must be ordered by computed cosine similarity descending; '
        f'expected {expected_pairs}, got {pairs}'
    )


def test_cleaned_dataset_csv():
    """Verify retained source data and the computed TruncatedSVD coordinates."""
    _, expected_rows = compute_reference()

    assert os.path.isfile(CLEANED_PATH), f'Missing {CLEANED_PATH}'
    with open(CLEANED_PATH, 'r', newline='') as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, 'CSV file is empty.'
    header = rows[0]
    expected_header = ['doc_id', 'title', 'text', 'pca_1', 'pca_2']
    assert header == expected_header, f'Expected header {expected_header}, got {header}'

    data_rows = rows[1:]
    assert len(data_rows) == 7, f'Expected exactly 7 remaining documents, found {len(data_rows)}.'

    remaining_ids = []
    seen_ids = set()
    for row in data_rows:
        assert len(row) == 5, f'Row does not have 5 columns: {row}'
        doc_id_str, title, text, pca_1_str, pca_2_str = row

        try:
            doc_id = int(doc_id_str)
            remaining_ids.append(doc_id)
        except ValueError:
            pytest.fail(f"Invalid doc_id '{doc_id_str}' in row: {row}")

        assert doc_id not in seen_ids, f'Duplicate doc_id {doc_id} in cleaned dataset.'
        seen_ids.add(doc_id)
        assert doc_id in expected_rows, f'Unexpected retained doc_id {doc_id}.'
        assert title == expected_rows[doc_id]['title'], f'Incorrect title for doc_id {doc_id}.'
        assert text == expected_rows[doc_id]['text'], f'Incorrect text for doc_id {doc_id}.'

        try:
            actual_pca = np.array([float(pca_1_str), float(pca_2_str)], dtype=float)
        except ValueError:
            pytest.fail(
                f"PCA values must be numeric, got pca_1='{pca_1_str}', "
                f"pca_2='{pca_2_str}' in row: {row}"
            )

        assert np.all(np.isfinite(actual_pca)), f'PCA values must be finite for doc_id {doc_id}.'
        np.testing.assert_allclose(
            actual_pca,
            expected_rows[doc_id]['pca'],
            rtol=1e-6,
            atol=1e-8,
            err_msg=f'Incorrect TruncatedSVD coordinates for doc_id {doc_id}',
        )

    expected_remaining_ids = [1, 2, 4, 5, 7, 9, 10]
    assert sorted(remaining_ids) == expected_remaining_ids, (
        f'Expected remaining doc_ids {expected_remaining_ids}, got {sorted(remaining_ids)}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
