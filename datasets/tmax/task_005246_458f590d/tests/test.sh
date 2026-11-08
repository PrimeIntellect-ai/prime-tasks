#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess

import pytest

DATASET_PATH = "/home/user/dataset.csv"
METRICS_PATH = "/home/user/metrics.json"
CPP_PATH = "/home/user/pipeline.cpp"
BINARY_PATH = "/tmp/verifier_pipeline_bin"


def parse_dataset(contents):
    lines = contents.strip().splitlines()
    assert lines and lines[0] == "id,f1,f2,label", "Dataset header is incorrect."
    data = []
    for line in lines[1:]:
        parts = line.split(',')
        data.append((int(parts[0]), float(parts[1]), float(parts[2]), int(parts[3])))
    assert len(data) == 100, "Dataset must contain exactly 100 data rows."
    return data


def expected_metrics(data):
    train = data[:80]
    test = data[80:]

    mean_f1 = sum(x[1] for x in train) / 80.0
    mean_f2 = sum(x[2] for x in train) / 80.0
    std_f1 = math.sqrt(sum((x[1] - mean_f1) ** 2 for x in train) / 79.0)
    std_f2 = math.sqrt(sum((x[2] - mean_f2) ** 2 for x in train) / 79.0)

    train_scaled = [
        (x[0], (x[1] - mean_f1) / std_f1, (x[2] - mean_f2) / std_f2, x[3])
        for x in train
    ]
    test_scaled = [
        (x[0], (x[1] - mean_f1) / std_f1, (x[2] - mean_f2) / std_f2, x[3])
        for x in test
    ]

    correct = 0
    for ts in test_scaled:
        best_dist = float('inf')
        best_label = -1
        best_id = float('inf')
        for tr in train_scaled:
            dist = math.sqrt((ts[1] - tr[1]) ** 2 + (ts[2] - tr[2]) ** 2)
            if dist < best_dist:
                best_dist = dist
                best_label = tr[3]
                best_id = tr[0]
            elif dist == best_dist and tr[0] < best_id:
                best_dist = dist
                best_label = tr[3]
                best_id = tr[0]
        if best_label == ts[3]:
            correct += 1

    return {
        "train_mean_f1": round(mean_f1, 4),
        "train_mean_f2": round(mean_f2, 4),
        "test_accuracy": round(correct / 20.0, 4),
    }


def validate_metrics(expected):
    assert os.path.exists(METRICS_PATH), f"Metrics file {METRICS_PATH} is missing."
    with open(METRICS_PATH, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {METRICS_PATH} is not valid JSON.")

    for key, value in expected.items():
        assert key in actual, f"Missing key '{key}' in {METRICS_PATH}"
        assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool), \
            f"Value for '{key}' must be numeric."
        assert math.isclose(actual[key], value, abs_tol=1e-4), \
            f"Value for '{key}' is incorrect. Expected {value}, got {actual[key]}"


def run_pipeline():
    if os.path.exists(METRICS_PATH):
        os.remove(METRICS_PATH)
    result = subprocess.run(
        [BINARY_PATH], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, \
        f"Compiled pipeline failed with exit code {result.returncode}: {result.stderr}"
    assert os.path.exists(METRICS_PATH), \
        "The compiled C++ pipeline did not generate /home/user/metrics.json."


def make_challenge_dataset():
    rng = secrets.SystemRandom()
    rows = []
    used_ids = {1, 900}

    # Identical feature vectors with different labels and IDs exercise the required
    # lower-ID tie break. The first test row exactly matches both vectors.
    tie_f1 = rng.randrange(1000, 9000) / 100.0
    tie_f2 = rng.randrange(1000, 9000) / 100.0
    rows.append((900, tie_f1, tie_f2, 0))
    rows.append((1, tie_f1, tie_f2, 1))

    for _ in range(78):
        while True:
            row_id = rng.randrange(10, 1000000)
            if row_id not in used_ids:
                used_ids.add(row_id)
                break
        f1 = rng.randrange(-5000, 15001) / 100.0
        f2 = rng.randrange(-5000, 15001) / 100.0
        rows.append((row_id, f1, f2, rng.randrange(2)))

    rows.append((rng.randrange(1000001, 2000000), tie_f1, tie_f2, 1))
    for _ in range(19):
        row_id = rng.randrange(2000001, 9000000)
        f1 = rng.randrange(-5000, 15001) / 100.0
        f2 = rng.randrange(-5000, 15001) / 100.0
        rows.append((row_id, f1, f2, rng.randrange(2)))

    return rows


def serialize_dataset(rows):
    lines = ["id,f1,f2,label"]
    lines.extend(f"{row_id},{f1:.2f},{f2:.2f},{label}" for row_id, f1, f2, label in rows)
    return "\n".join(lines) + "\n"


def test_pipeline_output_and_logic():
    assert os.path.exists(CPP_PATH), f"C++ source file {CPP_PATH} is missing."
    assert os.path.isfile(CPP_PATH), f"C++ source path {CPP_PATH} is not a regular file."
    assert os.path.exists(METRICS_PATH), f"Metrics file {METRICS_PATH} is missing."
    assert os.path.exists(DATASET_PATH), f"Dataset file {DATASET_PATH} is missing."

    with open(DATASET_PATH, 'rb') as f:
        original_dataset = f.read()
    with open(METRICS_PATH, 'rb') as f:
        original_metrics = f.read()

    original_data = parse_dataset(original_dataset.decode())
    # Preserve the original verifier's validation of the submitted metrics.
    validate_metrics(expected_metrics(original_data))

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", BINARY_PATH],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, \
        f"pipeline.cpp did not compile: {compile_result.stderr}"
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), \
        "Compilation did not produce an executable pipeline."

    try:
        # Require the executable itself to regenerate correct output on the
        # original dataset.
        run_pipeline()
        validate_metrics(expected_metrics(original_data))

        # Exercise the executable on unpredictable valid datasets so a
        # hardcoded metrics file cannot satisfy the C++ implementation task.
        for _ in range(2):
            challenge = make_challenge_dataset()
            with open(DATASET_PATH, 'w') as f:
                f.write(serialize_dataset(challenge))
            run_pipeline()
            validate_metrics(expected_metrics(challenge))
    finally:
        with open(DATASET_PATH, 'wb') as f:
            f.write(original_dataset)
        with open(METRICS_PATH, 'wb') as f:
            f.write(original_metrics)
        if os.path.exists(BINARY_PATH):
            os.remove(BINARY_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
