#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
import subprocess
import pytest


def test_predictions_file_exists():
    pred_path = "/home/user/predictions.csv"
    assert os.path.exists(pred_path), f"The output file {pred_path} was not found."
    assert os.path.isfile(pred_path), f"{pred_path} is not a file."


def build_truth():
    embeddings = {}
    with open("/home/user/items.csv", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            out = subprocess.check_output(
                ["/app/embed_oracle", row["item_text"]], text=True
            ).strip()
            embeddings[row["item_id"]] = [float(x) for x in out.split()]

    history = {}
    total_clicks = 0
    total_impressions = 0
    with open("/home/user/history.csv", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            clicks = int(row["clicks"])
            impressions = int(row["impressions"])
            total_clicks += clicks
            total_impressions += impressions
            history.setdefault(row["user_id"], []).append({
                "item": row["item_id"],
                "clicks": clicks,
                "impressions": impressions,
            })

    alpha = total_clicks
    beta = total_impressions - total_clicks
    global_mean = alpha / (alpha + beta)

    for records in history.values():
        for record in records:
            record["smoothed_ctr"] = (
                (record["clicks"] + alpha)
                / (record["impressions"] + alpha + beta)
            )

    def cosine_similarity(v1, v2):
        dot = sum(a * b for a, b in zip(v1, v2))
        n1 = math.sqrt(sum(a * a for a in v1))
        n2 = math.sqrt(sum(b * b for b in v2))
        return dot / (n1 * n2)

    truth = {}
    with open("/home/user/queries.csv", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            user_id = row["user_id"]
            target_item_id = row["target_item_id"]
            if user_id not in history:
                prediction = global_mean
            else:
                numerator = 0.0
                denominator = 0.0
                target_embedding = embeddings[target_item_id]
                for record in history[user_id]:
                    similarity = cosine_similarity(
                        target_embedding, embeddings[record["item"]]
                    )
                    weight = max(0, similarity)
                    numerator += weight * record["smoothed_ctr"]
                    denominator += weight
                prediction = global_mean if denominator == 0 else numerator / denominator
            truth[(user_id, target_item_id)] = float(f"{prediction:.6f}")
    return truth


def test_predictions_mse():
    pred_path = "/home/user/predictions.csv"
    assert os.path.exists(pred_path), f"Predictions file {pred_path} missing."

    truth = build_truth()
    preds = {}
    with open(pred_path, newline="") as f:
        reader = csv.DictReader(f)
        assert "user_id" in reader.fieldnames and "target_item_id" in reader.fieldnames and "predicted_ctr" in reader.fieldnames, \
            "Predictions file is missing required columns: user_id, target_item_id, predicted_ctr"

        for row in reader:
            try:
                preds[(row["user_id"], row["target_item_id"])] = float(row["predicted_ctr"])
            except ValueError:
                pytest.fail(f"Invalid predicted_ctr value for {row['user_id']}, {row['target_item_id']}")

    missing_keys = set(truth.keys()) - set(preds.keys())
    assert not missing_keys, f"Predictions file is missing predictions for queries: {missing_keys}"

    mse = 0.0
    for key in truth:
        error = truth[key] - preds[key]
        mse += error * error
    mse /= len(truth)

    threshold = 0.0001
    assert mse <= threshold, f"MSE is {mse:.6f}, which is greater than the threshold {threshold}. Predictions are not accurate enough."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
