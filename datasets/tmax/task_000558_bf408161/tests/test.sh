#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import pytest
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.naive_bayes import MultinomialNB


def compute_expected_predictions():
    df = pd.read_csv('/home/user/reviews.csv')

    def valid_review_id(value):
        try:
            int(value)
            return True
        except (TypeError, ValueError, OverflowError):
            return False

    valid_mask = df['review_id'].map(valid_review_id) & df['text'].map(
        lambda value: isinstance(value, str) and value != ''
    )
    cleaned = df.loc[valid_mask].copy()
    cleaned['review_id'] = cleaned['review_id'].map(int)

    vectorizer = TfidfVectorizer(stop_words='english', max_features=50)
    features = vectorizer.fit_transform(cleaned['text'])

    labeled_mask = cleaned['category'].isin(['electronics', 'books']).to_numpy()
    unlabeled_mask = (cleaned['category'].isna() | (cleaned['category'] == '')).to_numpy()

    model = MultinomialNB()
    model.fit(features[labeled_mask], cleaned.loc[labeled_mask, 'category'])
    probabilities = model.predict_proba(features[unlabeled_mask])
    class_indexes = {name: index for index, name in enumerate(model.classes_)}

    expected = []
    unlabeled_rows = cleaned.loc[unlabeled_mask]
    for row_position, review_id in enumerate(unlabeled_rows['review_id']):
        expected.append({
            'review_id': int(review_id),
            'prob_books': float(probabilities[row_position, class_indexes['books']]),
            'prob_electronics': float(probabilities[row_position, class_indexes['electronics']]),
        })
    return sorted(expected, key=lambda row: row['review_id'])


def test_predictions_csv_exists_and_format():
    pred_path = '/home/user/predictions.csv'
    assert os.path.isfile(pred_path), f"Expected output file {pred_path} does not exist."

    with open(pred_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        assert fieldnames is not None, f"File {pred_path} is empty."

        expected_cols = ['review_id', 'prob_books', 'prob_electronics']
        assert fieldnames == expected_cols, f"Expected columns {expected_cols}, got {fieldnames}."

        rows = list(reader)

    assert len(rows) == 4, f"Expected 4 rows in predictions.csv, got {len(rows)}."

    review_ids = []
    parsed_rows = []
    for row in rows:
        try:
            rid = int(row['review_id'])
            review_ids.append(rid)
        except ValueError:
            pytest.fail(f"review_id {row['review_id']} is not an integer.")

        try:
            p_books = float(row['prob_books'])
            p_elec = float(row['prob_electronics'])
        except ValueError:
            pytest.fail("Probabilities must be valid floats.")

        assert abs(p_books + p_elec - 1.0) < 1e-4, f"Probabilities {p_books} and {p_elec} do not sum to 1."
        parsed_rows.append((rid, p_books, p_elec))

    expected_ids = [6, 7, 9, 10]
    assert review_ids == expected_ids, f"Expected review_ids {expected_ids} (sorted), got {review_ids}."

    expected_rows = compute_expected_predictions()
    for actual, expected in zip(parsed_rows, expected_rows):
        rid, p_books, p_elec = actual
        assert rid == expected['review_id']
        assert math.isfinite(p_books) and math.isfinite(p_elec), 'Probabilities must be finite.'
        assert p_books == pytest.approx(expected['prob_books'], rel=1e-7, abs=1e-8), \
            f"Incorrect books probability for review_id {rid}."
        assert p_elec == pytest.approx(expected['prob_electronics'], rel=1e-7, abs=1e-8), \
            f"Incorrect electronics probability for review_id {rid}."


def test_benchmark_json():
    bench_path = '/home/user/benchmark.json'
    assert os.path.isfile(bench_path), f"Expected benchmark file {bench_path} does not exist."

    with open(bench_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {bench_path} is not valid JSON.")

    assert isinstance(data, dict), "Benchmark JSON must be an object/dict."
    assert "avg_inference_time_sec" in data, "Key 'avg_inference_time_sec' missing from benchmark.json."

    avg_time = data["avg_inference_time_sec"]
    assert isinstance(avg_time, float), f"Expected float for avg_inference_time_sec, got {type(avg_time)}."
    assert avg_time >= 0.0, "Average inference time should be non-negative."
    assert math.isfinite(avg_time), "Average inference time must be finite."
    assert avg_time > 0.0, "Average inference time must be a measured positive duration."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
