#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import pandas as pd
import numpy as np
import pytest


def test_results_iou():
    results_path = '/home/user/results.csv'
    assert os.path.isfile(results_path), f"Output file {results_path} is missing."

    docs_path = '/app/documents.csv'
    assert os.path.isfile(docs_path), f"Documents file {docs_path} is missing."

    docs_df = pd.read_csv(
        docs_path,
        header=None,
        names=['doc_id', 'v1', 'v2', 'v3', 'v4', 'v5']
    )

    # Re-derive the query vector for "find the latest financial reports".
    query_vec = np.array([0.4, 1.3, 1.4, 0.8, 1.0])
    query_norm = np.linalg.norm(query_vec)

    def cosine_sim(row):
        vec = np.array([row['v1'], row['v2'], row['v3'], row['v4'], row['v5']])
        vec_norm = np.linalg.norm(vec)
        if vec_norm == 0 or query_norm == 0:
            return 0.0
        return np.dot(query_vec, vec) / (query_norm * vec_norm)

    docs_df['sim'] = docs_df.apply(cosine_sim, axis=1)
    truth_top_df = docs_df.sort_values(
        by='sim', ascending=False, kind='mergesort'
    ).head(10)
    truth_top = set(truth_top_df['doc_id'].astype(str))

    try:
        agent_df = pd.read_csv(results_path, header=None, names=['doc_id', 'score'])
        agent_top = set(agent_df['doc_id'].head(10).astype(str))
    except Exception as e:
        pytest.fail(f"Failed to read or parse {results_path}: {e}")

    # Preserve the original IoU assertion.
    intersection = len(agent_top.intersection(truth_top))
    union = len(agent_top.union(truth_top))
    iou = intersection / union if union > 0 else 0
    assert iou >= 0.8, (
        f"IoU metric failed. Computed IoU: {iou:.2f} (Threshold: >= 0.8).\n"
        f"Agent top 10: {agent_top}\n"
        f"Truth top 10: {truth_top}"
    )

    # Enforce the required no-header, two-column, exactly-ten-row format.
    try:
        with open(results_path, 'r', encoding='utf-8') as f:
            lines = f.read().splitlines()
    except Exception as e:
        pytest.fail(f"Failed to read {results_path}: {e}")

    assert len(lines) == 10, f"Expected exactly 10 rows, found {len(lines)}."

    parsed = []
    score_pattern = re.compile(r'^[+-]?[0-9]+\.[0-9]{4}$')
    for row_num, line in enumerate(lines, start=1):
        fields = line.split(',')
        assert len(fields) == 2, (
            f"Row {row_num} must contain exactly doc_id,similarity_score: {line!r}"
        )
        doc_id, score_text = fields
        assert doc_id != '', f"Row {row_num} has an empty document ID."
        assert score_pattern.fullmatch(score_text), (
            f"Row {row_num} score must be a finite decimal with exactly four "
            f"digits after the decimal point: {score_text!r}"
        )
        parsed.append((doc_id, score_text))

    expected = [
        (str(row.doc_id), format(float(row.sim), '.4f'))
        for row in truth_top_df.itertuples(index=False)
    ]

    actual_ids = [doc_id for doc_id, _ in parsed]
    expected_ids = [doc_id for doc_id, _ in expected]
    assert actual_ids == expected_ids, (
        "Document IDs must be the exact top 10 in descending similarity order.\n"
        f"Actual:   {actual_ids}\n"
        f"Expected: {expected_ids}"
    )

    for row_num, ((actual_id, actual_score), (_, expected_score)) in enumerate(
        zip(parsed, expected), start=1
    ):
        assert actual_score == expected_score, (
            f"Incorrect rounded similarity for {actual_id} on row {row_num}: "
            f"got {actual_score}, expected {expected_score}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
