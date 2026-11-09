#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile

import numpy as np
import pytest

WORKSPACE = "/home/user/workspace"
SOURCE = os.path.join(WORKSPACE, "knn_pipeline.c")
REQUIRED_EXE = os.path.join(WORKSPACE, "knn_pipeline_fixed")
REPORT = "/home/user/results/report.json"
TEST_EXE = "/tmp/knn_pipeline_test"
N = 1000
TRAIN_SIZE = 800
FEATURES = 5


def run_program(executable, cwd):
    result = subprocess.run(
        [executable], cwd=cwd, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    matches = re.findall(r"Test Accuracy:\s*([0-9]+\.[0-9]{4})", result.stdout)
    assert len(matches) == 1, (
        "Program must print exactly one 'Test Accuracy: <value>' line with four "
        f"decimal places. Output was:\n{result.stdout}"
    )
    return float(matches[0]), result.stdout


def knn_predictions(x, train_labels, stats_rows):
    """Independent KNN oracle using normalization statistics from stats_rows."""
    means = x[:stats_rows].mean(axis=0)
    stds = np.sqrt(((x[:stats_rows] - means) ** 2).mean(axis=0))
    stds[stds == 0] = 1.0
    z = (x - means) / stds

    predictions = []
    train = z[:TRAIN_SIZE]
    for query in z[TRAIN_SIZE:]:
        distances = np.sum((train - query) ** 2, axis=1)
        nearest = np.argsort(distances, kind="stable")[:3]
        predictions.append(1 if np.count_nonzero(train_labels[nearest] == 1) > 1 else 0)
    return np.asarray(predictions, dtype=np.int32)


def raw_knn_predictions(x, train_labels):
    predictions = []
    train = x[:TRAIN_SIZE]
    for query in x[TRAIN_SIZE:]:
        distances = np.sum((train - query) ** 2, axis=1)
        nearest = np.argsort(distances, kind="stable")[:3]
        predictions.append(1 if np.count_nonzero(train_labels[nearest] == 1) > 1 else 0)
    return np.asarray(predictions, dtype=np.int32)


def make_discriminating_dataset(case_number):
    """Create a hidden dataset where train-only and whole-dataset scaling differ."""
    rng = np.random.default_rng(secrets.randbits(64))

    for _ in range(100):
        train_scales = rng.uniform(0.15, 5.0, size=FEATURES)
        train = rng.normal(size=(TRAIN_SIZE, FEATURES)) * train_scales

        test_scale_factors = rng.uniform(0.1, 10.0, size=FEATURES)
        test_shifts = rng.uniform(-6.0, 6.0, size=FEATURES) * train_scales
        test = (
            rng.normal(size=(N - TRAIN_SIZE, FEATURES))
            * train_scales
            * test_scale_factors
            + test_shifts
        )

        x = np.vstack([train, test])
        # The C input has four decimal places, so derive all answers from those values.
        x = np.asarray(
            [[float(f"{value:.4f}") for value in row] for row in x],
            dtype=np.float64,
        )

        weights = rng.normal(size=FEATURES) / train_scales
        train_labels = ((x[:TRAIN_SIZE] @ weights) > 0).astype(np.int32)

        fixed_predictions = knn_predictions(x, train_labels, TRAIN_SIZE)
        leaked_predictions = knn_predictions(x, train_labels, N)
        raw_predictions = raw_knn_predictions(x, train_labels)

        if (
            np.count_nonzero(fixed_predictions != leaked_predictions) < 8
            or np.count_nonzero(fixed_predictions != raw_predictions) < 8
        ):
            continue

        flip_count = 23 if case_number == 0 else 67
        flip_indices = rng.choice(N - TRAIN_SIZE, size=flip_count, replace=False)
        test_labels = fixed_predictions.copy()
        test_labels[flip_indices] ^= 1

        expected = np.mean(fixed_predictions == test_labels)
        leaked_accuracy = np.mean(leaked_predictions == test_labels)
        raw_accuracy = np.mean(raw_predictions == test_labels)
        if abs(expected - leaked_accuracy) < 0.004 or abs(expected - raw_accuracy) < 0.004:
            continue

        labels = np.concatenate([train_labels, test_labels])
        return x, labels, float(expected)

    pytest.fail("Could not construct a discriminating normalization test dataset")


def write_dataset(path, x, labels):
    with open(path, "w") as handle:
        for row, label in zip(x, labels):
            handle.write(",".join(f"{value:.4f}" for value in row))
            handle.write(f",{int(label)}\n")


def test_report_json_exists_and_correct():
    assert os.path.exists(REPORT), f"Report file {REPORT} is missing."
    with open(REPORT, "r") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail("report.json is not a valid JSON file.")

    assert data.get("leakage_fixed") is True, "The 'leakage_fixed' key must be set to true."
    acc = data.get("corrected_test_accuracy")
    assert acc is not None, "The 'corrected_test_accuracy' key is missing."
    assert isinstance(acc, (int, float)) and not isinstance(acc, bool), (
        "corrected_test_accuracy must be a JSON number"
    )
    assert abs(float(acc) - 0.5400) < 0.001, (
        f"Expected corrected test accuracy to be ~0.5400, but got {acc}"
    )


def test_c_code_fixed_and_produces_correct_output():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} is missing."
    compile_result = subprocess.run(
        ["gcc", "-O3", SOURCE, "-o", TEST_EXE, "-lm"],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE}:\n{compile_result.stderr}"
    )

    accuracy, _ = run_program(TEST_EXE, WORKSPACE)
    assert abs(accuracy - 0.5400) < 0.001, (
        f"Expected corrected test accuracy to be ~0.5400, got {accuracy:.4f}"
    )

    with open(REPORT, "r") as handle:
        report = json.load(handle)
    assert round(float(report["corrected_test_accuracy"]), 4) == round(accuracy, 4), (
        "The report accuracy must match the fixed program's console output to four decimals"
    )


def test_executable_exists_and_is_compiled_program():
    assert os.path.isfile(REQUIRED_EXE), f"Compiled executable {REQUIRED_EXE} is missing."
    assert os.access(REQUIRED_EXE, os.X_OK), f"File {REQUIRED_EXE} is not executable."
    with open(REQUIRED_EXE, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", (
            "knn_pipeline_fixed must be a compiled ELF executable"
        )
    accuracy, _ = run_program(REQUIRED_EXE, WORKSPACE)
    assert abs(accuracy - 0.5400) < 0.001, (
        f"Required executable produced {accuracy:.4f}, expected ~0.5400"
    )


def test_hidden_datasets_use_training_only_statistics():
    for case_number in range(2):
        x, labels, expected = make_discriminating_dataset(case_number)
        with tempfile.TemporaryDirectory(prefix="knn_hidden_") as directory:
            write_dataset(os.path.join(directory, "dataset.csv"), x, labels)
            source_accuracy, _ = run_program(TEST_EXE, directory)
            executable_accuracy, _ = run_program(REQUIRED_EXE, directory)

        expected_printed = float(f"{expected:.4f}")
        assert source_accuracy == expected_printed, (
            "Recompiled source did not implement train-only normalization: "
            f"expected {expected_printed:.4f}, got {source_accuracy:.4f}"
        )
        assert executable_accuracy == expected_printed, (
            "knn_pipeline_fixed did not implement train-only normalization: "
            f"expected {expected_printed:.4f}, got {executable_accuracy:.4f}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
