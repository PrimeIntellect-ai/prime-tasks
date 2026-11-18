#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess

import pandas as pd
from sklearn.linear_model import LogisticRegression

PIPELINE = "/home/user/pipeline.py"
TRAIN = "/home/user/train.csv"
TEST = "/home/user/test.csv"
PREDICTIONS = "/home/user/predictions.csv"

ORIGINAL_TRAIN = """id,category_id,v1,v2,target
1,10,0.5,1.2,0
2,,0.6,1.1,0
3,20,1.5,0.2,1
4,10,0.4,1.3,0
5,,1.6,0.1,1
6,20,1.4,0.3,1
7,30,0.9,0.9,0
"""

ORIGINAL_TEST = """id,category_id,v1,v2
8,10,0.55,1.25
9,,0.7,1.0
10,20,1.45,0.25
11,40,0.8,0.8
"""


def write_text(path, content):
    with open(path, "w", newline="") as f:
        f.write(content)


def run_pipeline():
    if os.path.exists(PREDICTIONS):
        os.remove(PREDICTIONS)
    result = subprocess.run(
        ["python3", PIPELINE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "pipeline.py failed when executed autonomously.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(PREDICTIONS), f"File {PREDICTIONS} is missing."


def read_predictions():
    with open(PREDICTIONS, "r", newline="") as f:
        reader = csv.DictReader(f)
        expected_header = ["id", "hash_key", "prediction"]
        assert reader.fieldnames == expected_header, (
            f"Incorrect header in predictions.csv. Expected {expected_header}, got {reader.fieldnames}."
        )
        return list(reader)


def derive_expected(train_path, test_path):
    train = pd.read_csv(train_path)
    test = pd.read_csv(test_path)

    train["category_id"] = pd.to_numeric(train["category_id"], errors="coerce").fillna(-1).astype(int)
    test["category_id"] = pd.to_numeric(test["category_id"], errors="coerce").fillna(-1).astype(int)

    means = train.groupby("category_id")["v1"].mean()
    train["cat_mean_v1"] = train["category_id"].map(means)
    test["cat_mean_v1"] = test["category_id"].map(means).fillna(0.0)

    features = ["v1", "v2", "cat_mean_v1"]
    model = LogisticRegression(random_state=42, solver="lbfgs")
    model.fit(train[features], train["target"])
    predictions = model.predict(test[features])

    return [
        {
            "id": str(int(row.id)),
            "hash_key": f"{int(row.category_id)}_{int(row.id)}",
            "prediction": str(int(prediction)),
        }
        for row, prediction in zip(test.itertuples(index=False), predictions)
    ]


def write_challenge(seed):
    rng = random.Random(seed)
    category_cycle = [None, 10, 20, 30]
    category_base = {-1: 0.25, 10: 0.75, 20: 1.35, 30: 1.85}

    train_rows = []
    for i in range(72):
        category = category_cycle[i % len(category_cycle)]
        normalized = -1 if category is None else category
        v1 = category_base[normalized] + rng.uniform(-0.42, 0.42)
        v2 = rng.uniform(0.05, 1.95)
        score = 1.25 * v1 - 0.72 * v2 + rng.uniform(-0.25, 0.25)
        target = int(score > 0.85)
        train_rows.append([1000 + i, "" if category is None else category, v1, v2, target])

    # Guarantee both classes while retaining a nontrivial learned boundary.
    train_rows[0][-1] = 0
    train_rows[-1][-1] = 1

    test_categories = [10, None, 20, 40, 30, 10, 20, None, 40, 30, 10, 20, 30, None, 40, 10, 20]
    test_rows = []
    for i, category in enumerate(test_categories):
        normalized = -1 if category is None else category
        base = category_base.get(normalized, 1.05)
        v1 = base + rng.uniform(-0.55, 0.55)
        v2 = rng.uniform(0.05, 1.95)
        test_rows.append([5000 + seed * 100 + i, "" if category is None else category, v1, v2])

    with open(TRAIN, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "category_id", "v1", "v2", "target"])
        writer.writerows(train_rows)
    with open(TEST, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "category_id", "v1", "v2"])
        writer.writerows(test_rows)


def assert_rows_equal(actual_rows, expected_rows):
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows in predictions.csv, but got {len(actual_rows)}."
    )
    for i, (expected, actual) in enumerate(zip(expected_rows, actual_rows)):
        assert actual["id"] == expected["id"], (
            f"Row {i+1}: expected id '{expected['id']}', got '{actual['id']}'."
        )
        assert actual["hash_key"] == expected["hash_key"], (
            f"Row {i+1}: expected hash_key '{expected['hash_key']}', got '{actual['hash_key']}'. "
            "This usually indicates a failure to prevent pandas from converting missing values to floats."
        )
        assert actual["prediction"] == expected["prediction"], (
            f"Row {i+1}: expected prediction '{expected['prediction']}', got '{actual['prediction']}'. "
            "This indicates incorrect modeling, feature engineering, or random state initialization."
        )


def test_pipeline_script_exists():
    assert os.path.isfile(PIPELINE), f"File {PIPELINE} is missing."


def test_pipeline_executes_and_produces_correct_outputs():
    old_train = open(TRAIN, "rb").read() if os.path.exists(TRAIN) else None
    old_test = open(TEST, "rb").read() if os.path.exists(TEST) else None
    try:
        # Preserve the original verifier's exact assertions, but first require the
        # submitted artifact itself to generate the output.
        write_text(TRAIN, ORIGINAL_TRAIN)
        write_text(TEST, ORIGINAL_TEST)
        run_pipeline()
        expected_rows = [
            {"id": "8", "hash_key": "10_8", "prediction": "0"},
            {"id": "9", "hash_key": "-1_9", "prediction": "1"},
            {"id": "10", "hash_key": "20_10", "prediction": "1"},
            {"id": "11", "hash_key": "40_11", "prediction": "0"},
        ]
        assert_rows_equal(read_predictions(), expected_rows)

        # Exercise the script on inputs unavailable when the submission was made.
        # Expected outputs are independently derived from the specified ETL/model.
        secret = int.from_bytes(os.urandom(8), "big")
        for trial in range(3):
            write_challenge((secret + trial) % 1000000000)
            expected = derive_expected(TRAIN, TEST)
            run_pipeline()
            assert_rows_equal(read_predictions(), expected)
    finally:
        if old_train is not None:
            with open(TRAIN, "wb") as f:
                f.write(old_train)
        if old_test is not None:
            with open(TEST, "wb") as f:
                f.write(old_test)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
