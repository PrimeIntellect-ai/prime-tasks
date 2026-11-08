#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import random
import subprocess
import pytest

EVALUATE_GO_PATH = "/home/user/evaluate.go"
METRICS_JSON_PATH = "/home/user/metrics.json"
DATASET_PATH = "/home/user/dataset.csv"


def compute_embedding(text):
    counts = [0.0] * 26
    total = 0
    for char in text:
        if 'a' <= char <= 'z':
            counts[ord(char) - ord('a')] += 1
            total += 1
        elif 'A' <= char <= 'Z':
            counts[ord(char) - ord('A')] += 1
            total += 1
    if total == 0:
        return counts
    return [c / total for c in counts]


def compute_l2_distance(v1, v2):
    return sum((a - b) ** 2 for a, b in zip(v1, v2))


def get_expected_metrics():
    rows = []
    with open(DATASET_PATH, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append({
                'id': int(row['id']),
                'category': row['category'],
                'embedding': compute_embedding(row['text'])
            })

    folds_accuracy = []

    for fold in range(5):
        test_start = fold * 20
        test_end = test_start + 20
        test_set = rows[test_start:test_end]
        train_set = rows[:test_start] + rows[test_end:]

        correct = 0
        for test_item in test_set:
            best_dist = float('inf')
            best_train_item = None

            for train_item in train_set:
                dist = compute_l2_distance(test_item['embedding'], train_item['embedding'])
                if dist < best_dist:
                    best_dist = dist
                    best_train_item = train_item
                elif math.isclose(dist, best_dist, rel_tol=1e-9, abs_tol=1e-11):
                    if train_item['id'] < best_train_item['id']:
                        best_train_item = train_item

            if best_train_item['category'] == test_item['category']:
                correct += 1

        folds_accuracy.append(correct / 20.0)

    mean_accuracy = sum(folds_accuracy) / 5.0
    return folds_accuracy, mean_accuracy


def run_submission():
    if os.path.exists(METRICS_JSON_PATH):
        os.remove(METRICS_JSON_PATH)
    result = subprocess.run(
        ["go", "run", EVALUATE_GO_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"go run evaluate.go failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(METRICS_JSON_PATH), (
        "Running evaluate.go did not generate /home/user/metrics.json"
    )


def load_metrics():
    try:
        with open(METRICS_JSON_PATH, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {METRICS_JSON_PATH} is not valid JSON.")


@pytest.fixture(scope="module", autouse=True)
def execute_evaluator():
    run_submission()


def test_evaluate_go_exists():
    assert os.path.exists(EVALUATE_GO_PATH), f"Go file {EVALUATE_GO_PATH} does not exist."
    assert os.path.isfile(EVALUATE_GO_PATH), f"Path {EVALUATE_GO_PATH} is not a file."


def test_metrics_json_exists_and_valid():
    assert os.path.exists(METRICS_JSON_PATH), f"Metrics file {METRICS_JSON_PATH} does not exist."

    data = load_metrics()

    assert "folds_accuracy" in data, "Missing 'folds_accuracy' in metrics.json"
    assert "mean_accuracy" in data, "Missing 'mean_accuracy' in metrics.json"
    assert "avg_inference_us" in data, "Missing 'avg_inference_us' in metrics.json"

    assert isinstance(data["folds_accuracy"], list), "'folds_accuracy' must be a list"
    assert len(data["folds_accuracy"]) == 5, "'folds_accuracy' must have exactly 5 elements"
    assert isinstance(data["mean_accuracy"], (int, float)), "'mean_accuracy' must be a number"
    assert isinstance(data["avg_inference_us"], int), "'avg_inference_us' must be an integer"
    assert data["avg_inference_us"] > 0, "'avg_inference_us' must be > 0"


def test_metrics_accuracy_values():
    data = load_metrics()
    expected_folds, expected_mean = get_expected_metrics()

    actual_folds = data["folds_accuracy"]
    actual_mean = data["mean_accuracy"]

    for i, (actual, expected) in enumerate(zip(actual_folds, expected_folds)):
        assert math.isclose(actual, expected, abs_tol=1e-5), \
            f"Fold {i+1} accuracy mismatch. Expected {expected}, got {actual}"

    assert math.isclose(actual_mean, expected_mean, abs_tol=1e-5), \
        f"Mean accuracy mismatch. Expected {expected_mean}, got {actual_mean}"


def test_program_recomputes_metrics_for_valid_changed_dataset():
    with open(DATASET_PATH, 'rb') as f:
        original_dataset = f.read()

    rng = random.Random(9173)
    categories = ["News", "Sports", "Entertainment", "Tech"]
    alphabet = "abcdefghijklmnopqrstuvwxyz"

    try:
        with open(DATASET_PATH, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(["id", "category", "text"])
            for row_id in range(1, 101):
                category = categories[rng.randrange(len(categories))]
                if row_id % 17 == 0:
                    text = "1234 !!!"
                else:
                    chars = []
                    for _ in range(30 + (row_id % 13)):
                        char = alphabet[rng.randrange(len(alphabet))]
                        if rng.randrange(3) == 0:
                            char = char.upper()
                        chars.append(char)
                        if rng.randrange(7) == 0:
                            chars.append(" -! ")
                    text = ''.join(chars)
                writer.writerow([row_id, category, text])

        with open(DATASET_PATH, 'rb') as f:
            generated_dataset = f.read()

        expected_folds, expected_mean = get_expected_metrics()
        run_submission()

        with open(DATASET_PATH, 'rb') as f:
            assert f.read() == generated_dataset, "evaluate.go must not modify dataset.csv"

        data = load_metrics()
        assert "folds_accuracy" in data, "Missing 'folds_accuracy' in metrics.json"
        assert "mean_accuracy" in data, "Missing 'mean_accuracy' in metrics.json"
        assert "avg_inference_us" in data, "Missing 'avg_inference_us' in metrics.json"
        assert isinstance(data["folds_accuracy"], list), "'folds_accuracy' must be a list"
        assert len(data["folds_accuracy"]) == 5, "'folds_accuracy' must have exactly 5 elements"
        assert isinstance(data["mean_accuracy"], (int, float)), "'mean_accuracy' must be a number"
        assert isinstance(data["avg_inference_us"], int), "'avg_inference_us' must be an integer"
        assert data["avg_inference_us"] > 0, "'avg_inference_us' must be > 0"

        for i, (actual, expected) in enumerate(zip(data["folds_accuracy"], expected_folds)):
            assert math.isclose(actual, expected, abs_tol=1e-5), \
                f"Changed-dataset fold {i+1} mismatch. Expected {expected}, got {actual}"
        assert math.isclose(data["mean_accuracy"], expected_mean, abs_tol=1e-5), \
            f"Changed-dataset mean mismatch. Expected {expected_mean}, got {data['mean_accuracy']}"
    finally:
        with open(DATASET_PATH, 'wb') as f:
            f.write(original_dataset)
        run_submission()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
