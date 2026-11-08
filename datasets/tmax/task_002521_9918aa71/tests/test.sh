#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import subprocess
import sys

import numpy as np
import pytest


@pytest.fixture(scope="session", autouse=True)
def run_submission_script():
    script_path = "/home/user/generate_data.py"
    assert os.path.isfile(script_path), "generate_data.py is missing"

    for path in (
        "/home/user/validation.log",
        "/home/user/experiment_config.json",
        "/home/user/training_data.csv",
    ):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        result = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("generate_data.py timed out")

    assert result.returncode == 0, (
        "generate_data.py exited with status "
        f"{result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_generate_data_script_exists():
    assert os.path.isfile("/home/user/generate_data.py"), "generate_data.py is missing"


def test_validation_log():
    log_path = "/home/user/validation.log"
    assert os.path.isfile(log_path), "validation.log is missing"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"Expected 'SUCCESS' in validation.log, got '{content}'"


def test_experiment_config():
    config_path = "/home/user/experiment_config.json"
    assert os.path.isfile(config_path), "experiment_config.json is missing"
    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            assert False, "experiment_config.json is not a valid JSON file"

    assert isinstance(config, dict), "experiment_config.json must contain a JSON object"
    assert set(config.keys()) == {"seed", "num_samples", "noise_mean", "noise_std"}, (
        f"Config must contain exactly the required keys, got {sorted(config.keys())}"
    )
    assert config.get("seed") == 42, f"Expected seed to be 42, got {config.get('seed')}"
    assert config.get("num_samples") == 1000, f"Expected num_samples to be 1000, got {config.get('num_samples')}"
    assert config.get("noise_mean") == 0.0, f"Expected noise_mean to be 0.0, got {config.get('noise_mean')}"
    assert config.get("noise_std") == 0.5, f"Expected noise_std to be 0.5, got {config.get('noise_std')}"
    assert type(config["seed"]) is int, "seed must be a JSON integer"
    assert type(config["num_samples"]) is int, "num_samples must be a JSON integer"
    assert type(config["noise_mean"]) in (int, float) and not isinstance(config["noise_mean"], bool), "noise_mean must be numeric"
    assert type(config["noise_std"]) in (int, float) and not isinstance(config["noise_std"], bool), "noise_std must be numeric"


def test_training_data_csv():
    csv_path = "/home/user/training_data.csv"
    assert os.path.isfile(csv_path), "training_data.csv is missing"

    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            assert False, "training_data.csv is empty"

        assert headers == ["x", "y"], f"CSV headers must be ['x', 'y'], got {headers}"

        rows = list(reader)
        assert len(rows) == 1000, f"CSV must have exactly 1000 data rows, found {len(rows)}"

        x_vals = []
        y_vals = []
        for i, row in enumerate(rows):
            assert len(row) == 2, f"Row {i+1} does not have exactly 2 columns"
            try:
                x_vals.append(float(row[0]))
                y_vals.append(float(row[1]))
            except ValueError:
                assert False, f"Row {i+1} contains non-numeric data: {row}"

    # Preserve the original endpoint assertions.
    assert abs(x_vals[0] - 0.0) < 1e-5, f"First x value should be 0.0, got {x_vals[0]}"
    assert abs(x_vals[-1] - 10 * math.pi) < 1e-5, f"Last x value should be 10*pi, got {x_vals[-1]}"

    expected_first_y = 0.24835707650561636
    assert abs(y_vals[0] - expected_first_y) < 1e-2, f"First y value expected ~{expected_first_y}, got {y_vals[0]}"

    mean_y = sum(y_vals) / len(y_vals)
    var_y_pop = sum((y - mean_y)**2 for y in y_vals) / len(y_vals)
    var_y_sample = sum((y - mean_y)**2 for y in y_vals) / (len(y_vals) - 1)

    assert -0.2 < mean_y < 0.2, f"Mean of y ({mean_y}) is not strictly between -0.2 and 0.2"
    assert (2.5 < var_y_pop < 4.0) or (2.5 < var_y_sample < 4.0), f"Variance of y ({var_y_pop}) is not strictly between 2.5 and 4.0"

    # Verify every row against the deterministic seeded generation procedure.
    expected_x = np.linspace(0.0, 10.0 * np.pi, 1000)
    rng = np.random.RandomState(42)
    expected_y = 2.5 * np.sin(expected_x) + rng.normal(0.0, 0.5, 1000)

    actual_x = np.asarray(x_vals, dtype=float)
    actual_y = np.asarray(y_vals, dtype=float)
    assert np.all(np.isfinite(actual_x)), "All x values must be finite"
    assert np.all(np.isfinite(actual_y)), "All y values must be finite"
    assert np.allclose(actual_x, expected_x, rtol=1e-12, atol=1e-12), (
        "x values must be the 1000 evenly spaced points from 0 to 10*pi inclusive"
    )
    assert np.allclose(actual_y, expected_y, rtol=1e-12, atol=1e-12), (
        "y values do not match the deterministic seed-42 sinusoid-plus-noise sequence"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
