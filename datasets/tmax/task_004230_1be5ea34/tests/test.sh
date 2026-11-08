#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import re
import time
import statistics
from collections import Counter

import pytest
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.neighbors import NearestNeighbors


def get_golden_pairs():
    """Recompute the expected duplicate pairs from the source dataset."""
    data_path = '/home/user/data.csv'
    if not os.path.exists(data_path):
        pytest.fail(f"Missing data file: {data_path}")

    docs = []
    with open(data_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            docs.append((int(row['doc_id']), row['text']))

    tokenized_docs = []
    vocab = set()
    for doc_id, text in docs:
        tokens = re.findall(r"(?u)\b\w\w+\b", text.lower())
        tokenized_docs.append((doc_id, tokens))
        vocab.update(tokens)

    vocab = sorted(vocab)
    df = Counter()
    for doc_id, tokens in tokenized_docs:
        df.update(set(tokens))

    n_docs = len(docs)
    idf = {}
    for term in vocab:
        idf[term] = math.log((1 + n_docs) / (1 + df[term])) + 1.0

    tfidf_matrix = []
    for doc_id, tokens in tokenized_docs:
        tf = Counter(tokens)
        vec = [tf[term] * idf[term] for term in vocab]
        norm = math.sqrt(sum(v * v for v in vec))
        if norm > 0:
            vec = [v / norm for v in vec]
        tfidf_matrix.append((doc_id, vec))

    pairs = []
    for i in range(len(tfidf_matrix)):
        id1, vec1 = tfidf_matrix[i]
        for j in range(i + 1, len(tfidf_matrix)):
            id2, vec2 = tfidf_matrix[j]
            sim = sum(v1 * v2 for v1, v2 in zip(vec1, vec2))
            if sim >= 0.8499999999:
                pairs.append(tuple(sorted([id1, id2])))

    return sorted(set(pairs))


def measure_required_benchmark():
    """Independently execute the required 100 one-at-a-time brute-force queries."""
    data = pd.read_csv('/home/user/data.csv')
    assert len(data) >= 100, "Dataset must contain at least 100 documents"

    vectorizer = TfidfVectorizer(
        lowercase=True,
        stop_words='english',
        max_features=1000,
    )
    matrix = vectorizer.fit_transform(data['text'].fillna('').astype(str))
    model = NearestNeighbors(metric='cosine', algorithm='brute')
    model.fit(matrix)

    samples = []
    for _ in range(5):
        start = time.perf_counter()
        for i in range(100):
            model.kneighbors(matrix[i], n_neighbors=10, return_distance=True)
        samples.append(time.perf_counter() - start)

    return samples


def test_benchmark_time():
    path = '/home/user/benchmark_time.txt'
    assert os.path.exists(path), f"File not found: {path}"

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {path} is not a valid float: '{content}'")

    assert math.isfinite(val), f"Benchmark time must be finite, got {val}"
    assert val > 0, f"Benchmark time must be greater than 0, got {val}"

    samples = measure_required_benchmark()
    reference = statistics.median(samples)
    lower = reference / 5.0
    upper = reference * 5.0
    assert lower <= val <= upper, (
        "Reported benchmark time is inconsistent with the required 100 "
        "individual brute-force cosine queries. "
        f"Reported {val:.9f}s; verifier measurements were {samples}; "
        f"accepted range is [{lower:.9f}, {upper:.9f}]s."
    )


def test_duplicates_csv():
    path = '/home/user/duplicates.csv'
    assert os.path.exists(path), f"File not found: {path}"

    golden_pairs = get_golden_pairs()
    actual_pairs = []
    with open(path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f"{path} is empty")

        assert headers == ['id1', 'id2'], (
            f"Incorrect headers in {path}. Expected ['id1', 'id2'], got {headers}"
        )

        for i, row in enumerate(reader, start=2):
            assert len(row) == 2, f"Row {i} does not have exactly 2 columns"
            try:
                id1, id2 = int(row[0]), int(row[1])
            except ValueError:
                pytest.fail(f"Row {i} contains non-integer IDs: {row}")

            assert id1 < id2, f"Row {i} violates id1 < id2 rule: {id1} >= {id2}"
            actual_pairs.append((id1, id2))

    sorted_actual_pairs = sorted(actual_pairs)
    assert actual_pairs == sorted_actual_pairs, (
        f"{path} is not correctly sorted by id1 then id2"
    )

    assert actual_pairs == golden_pairs, (
        f"Duplicate pairs mismatch.\n"
        f"Expected: {golden_pairs}\n"
        f"Actual:   {actual_pairs}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
