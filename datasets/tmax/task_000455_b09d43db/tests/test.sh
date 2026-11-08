#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt
set -e

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re


def read_csv(path):
    assert os.path.isfile(path), f"{path} is missing. Did you compile and run the program?"
    with open(path, "r", newline="") as f:
        header = f.readline().rstrip("\r\n")
        assert header == "id,value,label", f"{path} has an incorrect header."
        reader = csv.DictReader(f, fieldnames=["id", "value", "label"])
        return list(reader)


def test_normalized_outputs():
    data_path = "/home/user/data.csv"
    assert os.path.isfile(data_path), f"{data_path} is missing. Did you accidentally delete it?"

    with open(data_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{data_path} is empty."
    train_size = int(len(rows) * 0.8)

    train_values = [float(row["value"]) for row in rows[:train_size]]
    train_mean = sum(train_values) / train_size
    train_var = sum((v - train_mean) ** 2 for v in train_values) / train_size
    train_std = math.sqrt(train_var)
    assert train_std > 0

    train_norm_path = "/home/user/train_norm.csv"
    train_norm_rows = read_csv(train_norm_path)
    assert len(train_norm_rows) == train_size, f"{train_norm_path} has incorrect number of rows."

    for i, row in enumerate(train_norm_rows):
        expected_val = (float(rows[i]["value"]) - train_mean) / train_std
        assert re.fullmatch(r"-?\d+\.\d{4}", row["value"]), \
            f"Row {i+1} in train_norm.csv does not use %.4f formatting."
        actual_val = float(row["value"])
        assert math.isclose(actual_val, expected_val, abs_tol=1e-3), \
            f"Row {i+1} in train_norm.csv has incorrect normalized value. Expected ~{expected_val:.4f}, got {actual_val:.4f}. Check your mean and std calculations."
        assert row["id"] == rows[i]["id"], f"Row {i+1} in train_norm.csv has incorrect id."
        assert row["label"] == rows[i]["label"], f"Row {i+1} in train_norm.csv has incorrect label."

    test_norm_path = "/home/user/test_norm.csv"
    test_norm_rows = read_csv(test_norm_path)
    assert len(test_norm_rows) == len(rows) - train_size, f"{test_norm_path} has incorrect number of rows."

    for i, row in enumerate(test_norm_rows):
        orig_idx = train_size + i
        expected_val = (float(rows[orig_idx]["value"]) - train_mean) / train_std
        assert re.fullmatch(r"-?\d+\.\d{4}", row["value"]), \
            f"Row {i+1} in test_norm.csv does not use %.4f formatting."
        actual_val = float(row["value"])
        assert math.isclose(actual_val, expected_val, abs_tol=1e-3), \
            f"Row {i+1} in test_norm.csv has incorrect normalized value. Expected ~{expected_val:.4f}, got {actual_val:.4f}. This indicates data leakage is still present or statistics are wrong."
        assert row["id"] == rows[orig_idx]["id"], f"Row {i+1} in test_norm.csv has incorrect id."
        assert row["label"] == rows[orig_idx]["label"], f"Row {i+1} in test_norm.csv has incorrect label."
TEST_EOF

# Replace the agent-writable fixture with a fresh, unpredictable 10-row case.
# The held-out values are deliberately far from the training distribution so
# whole-dataset normalization cannot accidentally pass.
python3 - << 'PY'
import secrets

rng = secrets.SystemRandom()
base = rng.randint(-500, 500)
scale = rng.randint(2, 13)
offsets = [0, 1, 3, 6, 10, 15, 21, 28, 60, 90]
start_id = rng.randint(1000, 9000)
labels = [rng.randint(0, 1) for _ in offsets]

with open("/home/user/data.csv", "w", newline="") as f:
    f.write("id,value,label\n")
    for i, offset in enumerate(offsets):
        value = base + scale * offset + 0.25
        f.write(f"{start_id + i},{value:.2f},{labels[i]}\n")
PY

test -f /home/user/normalize.c
rm -f /home/user/train_norm.csv /home/user/test_norm.csv /tmp/normalize_submission

# Compile and execute the submitted C source, rather than trusting prewritten CSVs.
gcc -std=c11 -O2 -o /tmp/normalize_submission /home/user/normalize.c -lm
timeout 10s /tmp/normalize_submission

python3 -m pytest /tmp/test_final_state.py -x --tb=short
echo "1" > /logs/verifier/reward.txt
