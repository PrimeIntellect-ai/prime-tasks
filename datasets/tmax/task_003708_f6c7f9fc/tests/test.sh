#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import shutil
import subprocess

import pytest

PROJECT = "/home/user/bayesian_data_prep"
DATASET = "/home/user/data/raw_measurements.csv"
EXPERIMENT = "/home/user/experiment"
TARGET_DIR = "/tmp/verifier_cargo_target"
BINARY = os.path.join(TARGET_DIR, "debug", "bayesian_data_prep")

ORIGINAL_CSV = """temp,pressure,humidity,vibration,failure_score
20.0,1.0,50.0,0.5,10.0
22.0,1.1,52.0,0.4,11.2
19.5,0.9,48.0,0.6,9.8
21.0,1.05,51.0,0.55,10.5
23.0,1.2,55.0,0.3,12.0
25.0,1.3,58.0,0.2,13.5
18.0,0.85,45.0,0.7,9.0
"""


def solve_map(rows):
    p = 4
    xtx = [[0.0 for _ in range(p)] for _ in range(p)]
    xty = [0.0 for _ in range(p)]
    for temp, pressure, humidity, vibration, target in rows:
        x = [1.0, temp, pressure, humidity]
        for i in range(p):
            xty[i] += x[i] * target
            for j in range(p):
                xtx[i][j] += x[i] * x[j]
    for i in range(p):
        xtx[i][i] += 2.0

    aug = [xtx[i][:] + [xty[i]] for i in range(p)]
    for col in range(p):
        pivot = max(range(col, p), key=lambda r: abs(aug[r][col]))
        assert abs(aug[pivot][col]) > 1e-12
        aug[col], aug[pivot] = aug[pivot], aug[col]
        divisor = aug[col][col]
        for j in range(col, p + 1):
            aug[col][j] /= divisor
        for row in range(p):
            if row == col:
                continue
            factor = aug[row][col]
            for j in range(col, p + 1):
                aug[row][j] -= factor * aug[col][j]
    return [aug[i][p] for i in range(p)]


def write_dataset(rows):
    os.makedirs(os.path.dirname(DATASET), exist_ok=True)
    with open(DATASET, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["temp", "pressure", "humidity", "vibration", "failure_score"])
        writer.writerows(rows)


def clear_experiment():
    if os.path.exists(EXPERIMENT):
        shutil.rmtree(EXPERIMENT)


def run_binary():
    clear_experiment()
    result = subprocess.run(
        [BINARY], cwd=PROJECT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"Rust program failed:\n{result.stdout}"
    assert os.path.isfile(os.path.join(EXPERIMENT, "metadata.json"))
    assert os.path.isfile(os.path.join(EXPERIMENT, "weights.json"))
    with open(os.path.join(EXPERIMENT, "metadata.json")) as f:
        metadata = json.load(f)
    with open(os.path.join(EXPERIMENT, "weights.json")) as f:
        weights = json.load(f)
    return metadata, weights


def test_rust_project_executes_pipeline_on_unseen_data():
    assert os.path.isdir(PROJECT), "Rust project /home/user/bayesian_data_prep does not exist."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."
    source = os.path.join(PROJECT, "src", "main.rs")
    assert os.path.isfile(source), "src/main.rs is missing."
    assert os.path.getsize(source) > 0, "src/main.rs is empty."

    shutil.rmtree(TARGET_DIR, ignore_errors=True)
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = TARGET_DIR
    build = subprocess.run(
        ["cargo", "build", "--offline", "--manifest-path", os.path.join(PROJECT, "Cargo.toml"),
         "--bin", "bayesian_data_prep"],
        cwd=PROJECT, env=env, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=180
    )
    assert build.returncode == 0, f"Rust project did not build from source:\n{build.stdout}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Built Rust executable is missing."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Built artifact is not a native executable."

    rng = secrets.SystemRandom()
    datasets = []
    for n in (9, 12):
        rows = []
        for _ in range(n):
            temp = rng.uniform(-15.0, 45.0)
            pressure = rng.uniform(0.35, 2.4)
            humidity = rng.uniform(5.0, 95.0)
            vibration = rng.uniform(-5000.0, 5000.0)
            target = rng.uniform(-30.0, 40.0) + 0.17 * temp - 0.8 * pressure + 0.03 * humidity
            rows.append((temp, pressure, humidity, vibration, target))
        datasets.append(rows)

    try:
        previous_weights = None
        for rows in datasets:
            write_dataset(rows)
            expected = solve_map(rows)
            metadata, weights = run_binary()
            assert isinstance(metadata, dict)
            assert metadata.get("n_samples") == len(rows)
            assert metadata.get("n_features") == 4
            assert isinstance(weights, list) and len(weights) == 4
            for i, (actual, wanted) in enumerate(zip(weights, expected)):
                assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
                assert math.isfinite(actual)
                assert abs(actual - wanted) < 1e-4, (
                    f"Weight {i} was {actual}, expected {wanted} for verifier-generated CSV"
                )
            if previous_weights is not None:
                assert any(abs(a - b) > 1e-3 for a, b in zip(weights, previous_weights)), \
                    "Weights did not respond to changed CSV input."
            previous_weights = weights
    finally:
        with open(DATASET, "w") as f:
            f.write(ORIGINAL_CSV)
        run_binary()


def test_experiment_directory_exists():
    """Test that the experiment directory exists."""
    assert os.path.isdir("/home/user/experiment"), "Directory /home/user/experiment does not exist."


def test_metadata_json():
    """Test that metadata.json exists and contains the correct values."""
    metadata_path = "/home/user/experiment/metadata.json"
    assert os.path.isfile(metadata_path), f"File {metadata_path} does not exist."

    with open(metadata_path, "r") as f:
        try:
            metadata = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {metadata_path} is not valid JSON.")

    assert isinstance(metadata, dict), "metadata.json must contain a JSON object."
    assert "n_samples" in metadata, "Key 'n_samples' missing in metadata.json"
    assert "n_features" in metadata, "Key 'n_features' missing in metadata.json"
    assert metadata["n_samples"] == 7, f"Expected n_samples=7, got {metadata['n_samples']}"
    assert metadata["n_features"] == 4, f"Expected n_features=4, got {metadata['n_features']}"


def test_weights_json():
    """Test that weights.json exists and contains the correct MAP estimates."""
    weights_path = "/home/user/experiment/weights.json"
    assert os.path.isfile(weights_path), f"File {weights_path} does not exist."

    with open(weights_path, "r") as f:
        try:
            weights = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {weights_path} is not valid JSON.")

    assert isinstance(weights, list), "weights.json must contain a JSON array."
    assert len(weights) == 4, f"Expected 4 elements in weights array, got {len(weights)}."

    expected_weights = [
        0.03813959954067339,
        0.05030239617260029,
        0.046036128859942735,
        0.17056463991823942
    ]

    for i, (w, expected_w) in enumerate(zip(weights, expected_weights)):
        assert isinstance(w, (int, float)), f"Weight at index {i} is not a number."
        assert abs(w - expected_w) < 1e-4, f"Weight at index {i} is {w}, expected approximately {expected_w}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
