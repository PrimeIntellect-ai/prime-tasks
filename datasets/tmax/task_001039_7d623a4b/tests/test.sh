#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.linear_model import LinearRegression


def compute_expected():
    df_a = pd.read_csv('/home/user/supplier_a.csv')
    df_b = pd.read_csv('/home/user/supplier_b.csv')

    for df in (df_a, df_b):
        df['price'] = pd.to_numeric(df['price'], errors='coerce')
        df['rating'] = pd.to_numeric(df['rating'], errors='coerce')
        df['price'] = df['price'].fillna(df['price'].median())
        df['rating'] = df['rating'].fillna(df['rating'].mean())

    descriptions = pd.concat([df_a['desc'], df_b['desc']], ignore_index=True)
    vectors = TfidfVectorizer().fit_transform(descriptions)
    count_a = len(df_a)
    similarities = cosine_similarity(vectors[:count_a], vectors[count_a:])

    matched_indices = []
    for scores in similarities:
        maximum = scores.max()
        tied_indices = np.flatnonzero(scores == maximum)
        matched_indices.append(min(tied_indices, key=lambda i: str(df_b.iloc[i]['id'])))

    features = np.array([
        [
            float(df_a.iloc[i]['price']),
            float(df_b.iloc[j]['price']),
            float(df_b.iloc[j]['rating']),
        ]
        for i, j in enumerate(matched_indices)
    ])
    target = df_a['rating'].to_numpy(dtype=float)
    predictions = LinearRegression().fit(features, target).predict(features)

    expected = {}
    for i, j in enumerate(matched_indices):
        expected[str(df_a.iloc[i]['id'])] = {
            'matched_id_B': str(df_b.iloc[j]['id']),
            'similarity_score': f'{similarities[i, j]:.4f}',
            'predicted_rating_A': f'{predictions[i]:.4f}',
        }
    return expected


def test_predictions_file_exists():
    path = '/home/user/predictions.csv'
    assert os.path.exists(path), f"File {path} does not exist. The task requires creating this file."


def test_predictions_format_and_matches():
    path = '/home/user/predictions.csv'
    if not os.path.exists(path):
        return  # Handled by previous test

    with open(path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, f"File {path} is empty."

        expected_header = ['id_A', 'matched_id_B', 'similarity_score', 'predicted_rating_A']
        assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}"

        rows = list(reader)
        assert len(rows) == 5, f"Expected exactly 5 rows of predictions, got {len(rows)}."
        assert all(len(row) == 4 for row in rows), "Each output row must contain exactly four columns."

        ids = [row[0] for row in rows]
        assert ids == sorted(ids), "The output rows are not sorted alphabetically by id_A."

        expected_matches = {
            'A1': 'B1',
            'A2': 'B3',
            'A3': 'B2',
            'A4': 'B6',
            'A5': 'B5'
        }
        assert ids == sorted(expected_matches), f"Expected one row for each id_A: {sorted(expected_matches)}."

        computed_expected = compute_expected()

        for row in rows:
            id_a, id_b, sim_score, pred_rating = row

            assert id_a in expected_matches, f"Unexpected id_A: {id_a}"
            assert id_b == expected_matches[id_a], f"For {id_a}, expected match {expected_matches[id_a]}, but got {id_b}."
            assert id_b == computed_expected[id_a]['matched_id_B'], (
                f"For {id_a}, recomputed match is {computed_expected[id_a]['matched_id_B']}, but got {id_b}."
            )

            try:
                float(sim_score)
                float(pred_rating)
            except ValueError:
                assert False, f"similarity_score and predicted_rating_A must be numbers. Got {sim_score} and {pred_rating}."

            assert len(sim_score.split('.')[-1]) <= 4, f"similarity_score {sim_score} is not rounded to 4 decimal places."
            assert len(pred_rating.split('.')[-1]) <= 4, f"predicted_rating_A {pred_rating} is not rounded to 4 decimal places."

            assert re.fullmatch(r'-?\d+\.\d{4}', sim_score), (
                f"similarity_score {sim_score} must have exactly 4 decimal places."
            )
            assert re.fullmatch(r'-?\d+\.\d{4}', pred_rating), (
                f"predicted_rating_A {pred_rating} must have exactly 4 decimal places."
            )
            assert sim_score == computed_expected[id_a]['similarity_score'], (
                f"For {id_a}, expected similarity_score {computed_expected[id_a]['similarity_score']}, got {sim_score}."
            )
            assert pred_rating == computed_expected[id_a]['predicted_rating_A'], (
                f"For {id_a}, expected predicted_rating_A {computed_expected[id_a]['predicted_rating_A']}, got {pred_rating}."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
