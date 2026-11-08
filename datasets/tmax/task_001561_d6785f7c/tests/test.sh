#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import math
import pytest

def test_predictions_generated_correctly():
    output_csv_path = "/home/user/output/predictions.csv"
    input_csv_path = "/home/user/data/input.csv"
    model_json_path = "/home/user/model/network.json"

    assert os.path.exists(output_csv_path), f"Output file not found at {output_csv_path}"
    assert os.path.isfile(output_csv_path), f"Expected {output_csv_path} to be a file"

    # Read input data
    inputs = []
    with open(input_csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            inputs.append({
                "id": row["id"],
                "features": [float(row["sensor_A"]), float(row["sensor_B"]), float(row["sensor_C"])]
            })

    # Read model architecture
    with open(model_json_path, "r") as f:
        network = json.load(f)

    W1 = network["layers"][0]["weights"]
    b1 = network["layers"][0]["biases"]
    W2 = network["layers"][1]["weights"]
    b2 = network["layers"][1]["biases"]

    # Compute expected predictions
    expected_predictions = {}
    for item in inputs:
        x = item["features"]

        # Layer 1: Dense + ReLU
        # z1 = x @ W1 + b1
        z1 = [sum(x[i] * W1[i][j] for i in range(len(x))) + b1[j] for j in range(len(b1))]
        a1 = [max(0, val) for val in z1]

        # Layer 2: Dense + Sigmoid
        # z2 = a1 @ W2 + b2
        z2 = [sum(a1[i] * W2[i][j] for i in range(len(a1))) + b2[j] for j in range(len(b2))]
        a2 = [1 / (1 + math.exp(-val)) for val in z2]

        # Thresholding
        pred = 1 if a2[0] >= 0.5 else 0
        expected_predictions[item["id"]] = pred

    # Read actual predictions
    actual_predictions = {}
    with open(output_csv_path, "r") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("Output CSV is empty")

        assert header == ["id", "prediction"], f"Expected header ['id', 'prediction'], got {header}"

        for row_idx, row in enumerate(reader, start=2):
            assert len(row) == 2, f"Expected exactly 2 columns in row {row_idx}, got {len(row)}"
            id_val = row[0]
            try:
                pred_val = int(float(row[1]))
            except ValueError:
                pytest.fail(f"Invalid prediction value '{row[1]}' in row {row_idx}")
            actual_predictions[id_val] = pred_val

    # Verify predictions
    assert len(actual_predictions) == len(expected_predictions), \
        f"Expected {len(expected_predictions)} predictions, but found {len(actual_predictions)}"

    for id_val, expected_pred in expected_predictions.items():
        assert id_val in actual_predictions, f"Missing prediction for id {id_val}"
        actual_pred = actual_predictions[id_val]
        assert actual_pred == expected_pred, \
            f"Incorrect prediction for id {id_val}. Expected {expected_pred}, got {actual_pred}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
