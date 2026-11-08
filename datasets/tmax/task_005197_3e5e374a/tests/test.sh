#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import numpy as np
import pandas as pd
from scipy.stats import ttest_ind
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

ORIGINAL_PATH = "/home/user/reviews.csv"
CLEANED_PATH = "/home/user/cleaned_reviews.csv"
METRICS_PATH = "/home/user/metrics.json"


def compute_expected():
    data = pd.read_csv(ORIGINAL_PATH)
    data = data.dropna(subset=["text"]).copy()

    vectorizer = TfidfVectorizer(
        max_features=500,
        stop_words="english",
        lowercase=True,
    )
    vectors = vectorizer.fit_transform(data["text"])

    valid_mask = data["rating"].between(1, 5, inclusive="both")
    corrupted_mask = ~valid_mask

    valid_lengths = data.loc[valid_mask, "text"].str.len()
    corrupted_lengths = data.loc[corrupted_mask, "text"].str.len()
    p_value = ttest_ind(
        valid_lengths,
        corrupted_lengths,
        equal_var=False,
    ).pvalue

    model = Ridge(alpha=1.0, random_state=42)
    model.fit(vectors[valid_mask.to_numpy()], data.loc[valid_mask, "rating"])

    valid_predictions = model.predict(vectors[valid_mask.to_numpy()])
    train_mse = mean_squared_error(
        data.loc[valid_mask, "rating"], valid_predictions
    )

    imputed = np.clip(
        model.predict(vectors[corrupted_mask.to_numpy()]), 1.0, 5.0
    )

    final_ratings = data["rating"].astype(float).copy()
    final_ratings.loc[corrupted_mask] = imputed
    expected_rows = pd.DataFrame({
        "id": data["id"],
        "text": data["text"],
        "final_rating": final_ratings,
    }).sort_values("id")

    expected_metrics = {
        "t_test_p_value": float(p_value),
        "train_mse": float(train_mse),
        "imputed_mean": float(np.mean(imputed)),
    }
    return expected_rows, expected_metrics


def test_cleaned_reviews_csv():
    assert os.path.isfile(CLEANED_PATH), f"Missing file: {CLEANED_PATH}"
    assert os.path.isfile(ORIGINAL_PATH), f"Missing file: {ORIGINAL_PATH}"

    original_valid = {}
    with open(ORIGINAL_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if not row["text"]:
                continue
            try:
                rating = float(row["rating"])
                if 1.0 <= rating <= 5.0:
                    original_valid[row["id"]] = rating
            except ValueError:
                pass

    with open(CLEANED_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "text", "final_rating"], \
            f"Incorrect columns in {CLEANED_PATH}. Expected ['id', 'text', 'final_rating']"
        actual_rows = list(reader)

    previous_id = -1
    for row in actual_rows:
        current_id = int(row["id"])
        assert current_id > previous_id, "Rows are not sorted by 'id' in ascending order."
        previous_id = current_id

        assert row["text"].strip() != "", f"Row with id {current_id} has missing text."

        final_rating = float(row["final_rating"])
        assert 1.0 <= final_rating <= 5.0, \
            f"final_rating {final_rating} for id {current_id} is out of bounds [1.0, 5.0]."

        if row["id"] in original_valid:
            expected_rating = original_valid[row["id"]]
            assert math.isclose(final_rating, expected_rating, rel_tol=1e-5), \
                f"Valid rating changed for id {current_id}. Expected {expected_rating}, got {final_rating}."

    expected_rows, _ = compute_expected()
    expected_records = expected_rows.to_dict("records")

    assert len(actual_rows) == len(expected_records), \
        f"Expected {len(expected_records)} cleaned rows, got {len(actual_rows)}."

    actual_ids = [int(row["id"]) for row in actual_rows]
    expected_ids = [int(row["id"]) for row in expected_records]
    assert actual_ids == expected_ids, \
        "cleaned_reviews.csv does not contain exactly all source rows with non-missing text."

    for actual, expected in zip(actual_rows, expected_records):
        current_id = int(actual["id"])
        assert actual["text"] == expected["text"], \
            f"Text changed for id {current_id}."
        actual_rating = float(actual["final_rating"])
        expected_rating = float(expected["final_rating"])
        assert math.isclose(actual_rating, expected_rating, rel_tol=1e-6, abs_tol=1e-6), \
            f"Incorrect final_rating for id {current_id}: expected {expected_rating}, got {actual_rating}."


def test_metrics_json():
    assert os.path.isfile(METRICS_PATH), f"Missing file: {METRICS_PATH}"

    with open(METRICS_PATH, "r", encoding="utf-8") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{METRICS_PATH} is not a valid JSON file."

    expected_keys = {"t_test_p_value", "train_mse", "imputed_mean"}
    assert set(metrics.keys()) == expected_keys, \
        f"Incorrect keys in metrics.json. Expected {expected_keys}, got {set(metrics.keys())}."

    p_val = metrics["t_test_p_value"]
    mse = metrics["train_mse"]
    imp_mean = metrics["imputed_mean"]

    assert isinstance(p_val, (int, float)), "t_test_p_value must be a float."
    assert 0.0 <= p_val <= 1.0, f"t_test_p_value {p_val} is out of bounds [0, 1]."

    assert isinstance(mse, (int, float)), "train_mse must be a float."
    assert mse >= 0.0, f"train_mse {mse} cannot be negative."

    assert isinstance(imp_mean, (int, float)), "imputed_mean must be a float."
    assert 1.0 <= imp_mean <= 5.0, f"imputed_mean {imp_mean} is out of bounds [1.0, 5.0]."

    _, expected_metrics = compute_expected()
    for key, expected_value in expected_metrics.items():
        actual_value = float(metrics[key])
        assert math.isclose(actual_value, expected_value, rel_tol=1e-6, abs_tol=1e-8), \
            f"Incorrect {key}: expected {expected_value}, got {actual_value}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
