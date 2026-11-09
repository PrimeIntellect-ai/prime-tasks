#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_test_scaled_csv_exists_and_correct():
    dataset_path = "/home/user/dataset.csv"
    output_path = "/home/user/test_scaled.csv"

    assert os.path.exists(dataset_path), f"Input file {dataset_path} is missing."
    assert os.path.exists(output_path), f"Output file {output_path} was not created."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

    train_feature_b = []
    test_rows = []

    with open(dataset_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            split = row.get("split", "").strip()
            feature_b_str = row.get("feature_B", "").strip()
            if not feature_b_str:
                continue
            feature_b = float(feature_b_str)

            if split == "train":
                train_feature_b.append(feature_b)
            elif split == "test":
                test_rows.append((row["id"], feature_b))

    assert train_feature_b, "No train rows found in dataset."
    train_min = min(train_feature_b)
    train_max = max(train_feature_b)
    train_range = train_max - train_min
    assert train_range > 0, "Train max and min are equal, cannot scale."

    expected_output = ["id,scaled_feature_B"]
    for row_id, feature_b in test_rows:
        scaled_val = (feature_b - train_min) / train_range
        expected_output.append(f"{row_id},{scaled_val:.4f}")

    expected_content = "\n".join(expected_output)

    with open(output_path, "r", newline="") as f:
        actual_content = f.read().strip()

    # Normalize line endings for comparison
    expected_lines = [line.strip() for line in expected_content.strip().splitlines()]
    actual_lines = [line.strip() for line in actual_content.strip().splitlines()]

    assert actual_lines == expected_lines, (
        f"Content of {output_path} does not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
