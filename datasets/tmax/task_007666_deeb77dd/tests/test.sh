#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import subprocess

SCRIPT_PATH = "/home/user/clean_pipeline.sh"
DATA_PATH = "/home/user/raw_data.csv"
RESULTS_PATH = "/home/user/cv_results.txt"
BEST_PATH = "/home/user/best_t.txt"


def compute_ground_truth():
    if not os.path.exists(DATA_PATH):
        return None

    data = []
    with open(DATA_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append({
                "id": int(row["id"]),
                "value": float(row["value"]),
                "label": int(row["label"]),
                "fold": int(row["fold"]),
            })

    results = {}
    for T in [2, 3, 4]:
        fold_accuracies = []
        for k in [1, 2, 3]:
            train_vals = [
                d["value"] for d in data
                if d["fold"] != k and d["label"] == 0
            ]
            n = len(train_vals)
            mean = sum(train_vals) / n if n > 0 else 0
            if n > 1:
                variance = sum((x - mean) ** 2 for x in train_vals) / (n - 1)
            else:
                variance = 0

            std = 0.0001 if variance == 0 else math.sqrt(variance)
            test_data = [d for d in data if d["fold"] == k]
            correct = 0
            for d in test_data:
                pred = 1 if abs(d["value"] - mean) > T * std else 0
                if pred == d["label"]:
                    correct += 1
            fold_accuracies.append(correct / len(test_data))

        results[T] = sum(fold_accuracies) / 3.0

    best_t = max(results.keys(), key=lambda t: (results[t], -t))
    return results, best_t


def remove_outputs():
    for path in (RESULTS_PATH, BEST_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_pipeline():
    remove_outputs()
    subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=15,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def assert_current_outputs():
    assert os.path.exists(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist."

    gt = compute_ground_truth()
    assert gt is not None, "raw_data.csv is missing, cannot compute ground truth."
    expected_results, expected_best_t = gt

    with open(RESULTS_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in {RESULTS_PATH}, got {len(lines)}."
    for i, T in enumerate([2, 3, 4]):
        expected_line = f"T={T}, Accuracy={expected_results[T]:.4f}"
        assert lines[i] == expected_line, (
            f"Line {i+1} mismatch. Expected '{expected_line}', got '{lines[i]}'."
        )

    assert os.path.exists(BEST_PATH), f"Best T file {BEST_PATH} does not exist."
    with open(BEST_PATH, "r") as f:
        content = f.read().strip()
    assert content == str(expected_best_t), (
        f"Expected best T to be '{expected_best_t}', got '{content}'."
    )


def write_dataset(rows):
    with open(DATA_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "value", "label", "fold"])
        writer.writerows(rows)


def test_pipeline_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_pipeline_runs_on_supplied_data():
    assert os.path.exists(DATA_PATH), "raw_data.csv is missing."
    run_pipeline()


def test_cv_results():
    assert os.path.exists(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist."

    gt = compute_ground_truth()
    assert gt is not None, "raw_data.csv is missing, cannot compute ground truth."
    expected_results, _ = gt

    with open(RESULTS_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in {RESULTS_PATH}, got {len(lines)}."
    for i, T in enumerate([2, 3, 4]):
        expected_line = f"T={T}, Accuracy={expected_results[T]:.4f}"
        assert lines[i] == expected_line, f"Line {i+1} mismatch. Expected '{expected_line}', got '{lines[i]}'."


def test_best_t():
    assert os.path.exists(BEST_PATH), f"Best T file {BEST_PATH} does not exist."

    gt = compute_ground_truth()
    assert gt is not None, "raw_data.csv is missing, cannot compute ground truth."
    _, expected_best_t = gt

    with open(BEST_PATH, "r") as f:
        content = f.read().strip()

    assert content == str(expected_best_t), f"Expected best T to be '{expected_best_t}', got '{content}'."


def test_pipeline_on_additional_datasets():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    datasets = [
        [
            (1, 0.0, 0, 1), (2, 0.0, 0, 1), (3, 0.00025, 1, 1),
            (4, 0.0, 0, 2), (5, 0.0, 0, 2), (6, 0.00025, 1, 2),
            (7, 0.0, 0, 3), (8, 0.0, 0, 3), (9, 0.00025, 1, 3),
        ],
        [
            (1, 9.0, 0, 1), (2, 10.0, 0, 1), (3, 11.0, 0, 1), (4, 13.0, 1, 1),
            (5, 9.0, 0, 2), (6, 10.0, 0, 2), (7, 11.0, 0, 2), (8, 13.0, 1, 2),
            (9, 9.0, 0, 3), (10, 10.0, 0, 3), (11, 11.0, 0, 3), (12, 13.0, 1, 3),
        ],
    ]

    try:
        for rows in datasets:
            write_dataset(rows)
            run_pipeline()
            assert_current_outputs()
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
