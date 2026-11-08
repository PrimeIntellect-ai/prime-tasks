#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import shutil
import subprocess
import tempfile
import uuid

import pytest

PYTHON_PATH = "/home/user/mlops_env/bin/python"
SCRIPT_PATH = "/home/user/summarize_artifacts.py"
CSV_PATH = "/home/user/experiment_summary.csv"
EXPERIMENTS_PATH = "/home/user/experiments"


def run_pipeline():
    result = subprocess.run(
        [PYTHON_PATH, SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Pipeline failed with exit code {result.returncode}. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(CSV_PATH), f"Pipeline did not create {CSV_PATH}"


def read_summary():
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)
    return fieldnames, rows


def derive_expected(experiments_path):
    expected = []
    for run_id in os.listdir(experiments_path):
        run_path = os.path.join(experiments_path, run_id)
        if not os.path.isdir(run_path):
            continue

        with open(os.path.join(run_path, "config.json"), "r") as f:
            config = json.load(f)
        with open(os.path.join(run_path, "metrics.csv"), "r", newline="") as f:
            metrics = list(csv.DictReader(f))

        final_row = max(metrics, key=lambda row: float(row["epoch"]))
        expected.append({
            "run_id": run_id,
            "learning_rate": float(config["learning_rate"]),
            "final_accuracy": float(final_row["accuracy"]),
            "model_size_bytes": os.path.getsize(os.path.join(run_path, "model.pt")),
        })

    return sorted(expected, key=lambda row: (-row["final_accuracy"], row["run_id"]))


def test_virtual_environment_exists():
    assert os.path.isfile(PYTHON_PATH), f"Virtual environment Python executable not found at {PYTHON_PATH}"

    result = subprocess.run([PYTHON_PATH, "-m", "pip", "show", "pandas"], capture_output=True, text=True)
    assert result.returncode == 0, "pandas is not installed in the virtual environment"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_experiment_summary_csv():
    # Remove any pre-generated answer and require the submitted script to recreate it.
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    run_pipeline()

    expected_rows = [
        {"run_id": "run_beta", "learning_rate": "0.001", "final_accuracy": "0.89", "model_size_bytes": "2048"},
        {"run_id": "run_gamma", "learning_rate": "0.005", "final_accuracy": "0.82", "model_size_bytes": "1536"},
        {"run_id": "run_alpha", "learning_rate": "0.01", "final_accuracy": "0.78", "model_size_bytes": "1024"}
    ]

    fieldnames, rows = read_summary()
    assert fieldnames == ["run_id", "learning_rate", "final_accuracy", "model_size_bytes"], \
        f"CSV columns are incorrect. Expected ['run_id', 'learning_rate', 'final_accuracy', 'model_size_bytes'], got {fieldnames}"

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(rows)} in the CSV"

    for i, (expected, actual) in enumerate(zip(expected_rows, rows)):
        assert actual["run_id"] == expected["run_id"], f"Row {i+1}: expected run_id {expected['run_id']}, got {actual['run_id']}"
        assert float(actual["learning_rate"]) == float(expected["learning_rate"]), f"Row {i+1}: expected learning_rate {expected['learning_rate']}, got {actual['learning_rate']}"
        assert float(actual["final_accuracy"]) == float(expected["final_accuracy"]), f"Row {i+1}: expected final_accuracy {expected['final_accuracy']}, got {actual['final_accuracy']}"
        assert int(actual["model_size_bytes"]) == int(expected["model_size_bytes"]), f"Row {i+1}: expected model_size_bytes {expected['model_size_bytes']}, got {actual['model_size_bytes']}"


def test_pipeline_processes_changed_artifacts():
    backup_root = tempfile.mkdtemp(prefix="experiments_backup_")
    backup_path = os.path.join(backup_root, "experiments")
    shutil.copytree(EXPERIMENTS_PATH, backup_path)

    rng = random.SystemRandom()
    suffix = uuid.uuid4().hex[:10]
    run_names = [f"a_tie_{suffix}", f"b_tie_{suffix}", f"z_best_{suffix}"]
    tie_accuracy = rng.randrange(610, 751) / 1000
    best_accuracy = tie_accuracy + rng.randrange(50, 151) / 1000
    learning_rates = [rng.randrange(1, 1000) / 1000000 for _ in run_names]
    model_sizes = [rng.randrange(257, 4097) for _ in run_names]

    try:
        shutil.rmtree(EXPERIMENTS_PATH)
        os.makedirs(EXPERIMENTS_PATH)

        for index, run_id in enumerate(run_names):
            run_path = os.path.join(EXPERIMENTS_PATH, run_id)
            os.makedirs(run_path)
            with open(os.path.join(run_path, "config.json"), "w") as f:
                json.dump({"learning_rate": learning_rates[index], "batch_size": 8 + index}, f)

            final_accuracy = best_accuracy if index == 2 else tie_accuracy
            # Highest epoch is deliberately not the last row, and an earlier epoch
            # has a distracting larger accuracy value.
            with open(os.path.join(run_path, "metrics.csv"), "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["epoch", "loss", "accuracy"])
                writer.writerow([9, 0.2, final_accuracy])
                writer.writerow([1, 0.8, 0.99])
                writer.writerow([4, 0.5, max(0.1, final_accuracy - 0.1)])

            with open(os.path.join(run_path, "model.pt"), "wb") as f:
                f.write(os.urandom(model_sizes[index]))

        expected_rows = derive_expected(EXPERIMENTS_PATH)
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        run_pipeline()
        fieldnames, actual_rows = read_summary()

        assert fieldnames == ["run_id", "learning_rate", "final_accuracy", "model_size_bytes"]
        assert len(actual_rows) == len(expected_rows)
        for actual, expected in zip(actual_rows, expected_rows):
            assert actual["run_id"] == expected["run_id"]
            assert float(actual["learning_rate"]) == pytest.approx(expected["learning_rate"])
            assert float(actual["final_accuracy"]) == pytest.approx(expected["final_accuracy"])
            assert int(actual["model_size_bytes"]) == expected["model_size_bytes"]
    finally:
        if os.path.exists(EXPERIMENTS_PATH):
            shutil.rmtree(EXPERIMENTS_PATH)
        shutil.copytree(backup_path, EXPERIMENTS_PATH)
        shutil.rmtree(backup_root)
        # Restore the requested final report for the original artifacts.
        subprocess.run([PYTHON_PATH, SCRIPT_PATH], capture_output=True, text=True, timeout=60)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
