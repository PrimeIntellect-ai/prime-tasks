#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess

import pytest

PIPELINE_DIR = "/home/user/ml_pipeline"
MAIN_CPP = os.path.join(PIPELINE_DIR, "main.cpp")
DATASET_CSV = os.path.join(PIPELINE_DIR, "dataset.csv")
RESULTS_CSV = os.path.join(PIPELINE_DIR, "benchmark_results.csv")
EXECUTABLE = os.path.join(PIPELINE_DIR, "pipeline_run")


def run_checked(command, timeout=120):
    result = subprocess.run(
        command,
        cwd=PIPELINE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command {command!r} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def build_pipeline():
    if os.path.lexists(EXECUTABLE):
        os.remove(EXECUTABLE)
    run_checked(["make"], timeout=120)
    assert os.path.isfile(EXECUTABLE), "make did not create pipeline_run."
    assert os.access(EXECUTABLE, os.X_OK), "pipeline_run is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pipeline_run must be a compiled executable."


def execute_pipeline():
    if os.path.lexists(RESULTS_CSV):
        os.remove(RESULTS_CSV)
    run_checked([EXECUTABLE], timeout=120)
    assert os.path.isfile(RESULTS_CSV), (
        "The compiled pipeline did not create benchmark_results.csv."
    )
    return read_and_validate_results()


def read_and_validate_results():
    assert os.path.isfile(RESULTS_CSV), f"Expected results file {RESULTS_CSV} does not exist."
    with open(RESULTS_CSV, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, "Results CSV is empty."
    expected_header = ["alpha", "cv_mse", "avg_inference_time_us"]
    assert rows[0] == expected_header, (
        f"CSV header is incorrect. Expected {expected_header}, got {rows[0]}."
    )

    data_rows = rows[1:]
    assert len(data_rows) == 3, f"Expected exactly 3 rows of data, found {len(data_rows)}."

    actual_alphas = []
    parsed = []
    for i, row in enumerate(data_rows):
        assert len(row) == 3, f"Row {i + 1} does not have exactly 3 columns: {row}"
        alpha_str, cv_mse_str, time_str = row
        try:
            alpha = float(alpha_str)
        except ValueError:
            pytest.fail(f"alpha value '{alpha_str}' in row {i + 1} is not valid.")
        try:
            cv_mse = float(cv_mse_str)
        except ValueError:
            pytest.fail(f"cv_mse value '{cv_mse_str}' in row {i + 1} is not a valid float.")
        try:
            time_val = float(time_str)
        except ValueError:
            pytest.fail(f"avg_inference_time_us value '{time_str}' in row {i + 1} is not valid.")

        assert math.isfinite(cv_mse), f"cv_mse must be finite, got {cv_mse_str}."
        assert math.isfinite(time_val), f"Inference time must be finite, got {time_str}."
        assert time_val >= 0, f"Inference time cannot be negative, got {time_val}."
        actual_alphas.append(alpha)
        parsed.append((alpha, cv_mse, time_val, cv_mse_str))

    expected_alphas = [0.1, 1.0, 10.0]
    assert actual_alphas == expected_alphas, (
        f"Expected alphas {expected_alphas}, got {actual_alphas}."
    )
    return parsed


def expected_cv_mses(rows):
    alphas = [0.1, 1.0, 10.0]
    k_folds = 5
    fold_size = len(rows) // k_folds
    totals = [0.0, 0.0, 0.0]

    for fold in range(k_folds):
        start = fold * fold_size
        end = (fold + 1) * fold_size
        train = rows[:start] + rows[end:]
        validation = rows[start:end]
        d = len(rows[0][0])

        means = [sum(x[j] for x, _ in train) / len(train) for j in range(d)]
        stds = []
        for j in range(d):
            variance = sum((x[j] - means[j]) ** 2 for x, _ in train) / len(train)
            stds.append(math.sqrt(variance))

        def scaled(x):
            return [(x[j] - means[j]) / (stds[j] + 1e-8) for j in range(d)]

        x_train = [scaled(x) for x, _ in train]
        y_train = [y for _, y in train]
        x_val = [scaled(x) for x, _ in validation]
        y_val = [y for _, y in validation]
        n_train = len(x_train)

        # The supplied train_ridge implementation's gradient can be represented
        # using X^T X and X^T y, avoiding a slow Python copy of its inner loop.
        gram = [[0.0] * d for _ in range(d)]
        target_product = [0.0] * d
        for x, y in zip(x_train, y_train):
            for j in range(d):
                target_product[j] += x[j] * y
                for q in range(d):
                    gram[j][q] += x[j] * x[q]
        for j in range(d):
            target_product[j] /= n_train
            for q in range(d):
                gram[j][q] /= n_train

        for alpha_index, alpha in enumerate(alphas):
            weights = [0.0] * d
            for _ in range(100):
                gradient = [
                    sum(gram[j][q] * weights[q] for q in range(d))
                    - target_product[j]
                    + alpha * weights[j]
                    for j in range(d)
                ]
                weights = [weights[j] - 0.01 * gradient[j] for j in range(d)]

            mse = 0.0
            for x, y in zip(x_val, y_val):
                prediction = sum(weights[j] * x[j] for j in range(d))
                mse += (prediction - y) ** 2
            totals[alpha_index] += mse / len(x_val)

    return [value / k_folds for value in totals]


def write_secret_dataset():
    seed = int.from_bytes(os.urandom(16), "big")
    rng = random.Random(seed)
    coefficients = [rng.uniform(-3.0, 3.0) for _ in range(5)]
    rows = []

    # Fold-dependent feature locations make global and training-fold scaling
    # measurably different. Values are rounded exactly as they are written.
    for i in range(5000):
        fold = i // 1000
        features = []
        for j in range(5):
            location = (fold - 2) * (1.7 + 0.35 * j) + rng.uniform(-0.4, 0.4)
            scale = 0.7 + 0.3 * j
            value = rng.gauss(location, scale)
            features.append(float(f"{value:.4f}"))
        target = sum(coefficients[j] * features[j] for j in range(5))
        target += rng.gauss(0.0, 1.3)
        target = float(f"{target:.4f}")
        rows.append((features, target))

    with open(DATASET_CSV, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        for features, target in rows:
            writer.writerow([f"{v:.4f}" for v in features] + [f"{target:.4f}"])
    return rows


@pytest.fixture(scope="session", autouse=True)
def preserve_files_and_build():
    with open(DATASET_CSV, "rb") as f:
        original_dataset = f.read()
    original_results = None
    if os.path.isfile(RESULTS_CSV):
        with open(RESULTS_CSV, "rb") as f:
            original_results = f.read()
    build_pipeline()
    yield
    with open(DATASET_CSV, "wb") as f:
        f.write(original_dataset)
    if original_results is None:
        if os.path.lexists(RESULTS_CSV):
            os.remove(RESULTS_CSV)
    else:
        with open(RESULTS_CSV, "wb") as f:
            f.write(original_results)


def test_data_leak_fixed_in_main_cpp():
    assert os.path.isfile(MAIN_CPP), f"Source file {MAIN_CPP} is missing."
    with open(MAIN_CPP, "r") as f:
        content = f.read()

    assert "<chrono>" in content, "Expected <chrono> to be included for inference benchmarking."
    buggy_call_pattern = r"scale_data_globally\s*\(\s*data\s*\)\s*;"
    assert not re.search(buggy_call_pattern, content), (
        "The data leak appears to be unfixed: global scaling is still called on the full dataset."
    )

    clock = r"(?:high_resolution_clock|steady_clock)\s*::\s*now\s*\(\s*\)"
    timed_prediction = clock + r"[\s\S]{0,1500}?\bpredict\s*\([^;]*\)[\s\S]{0,1500}?" + clock
    assert re.search(timed_prediction, content), (
        "Expected a predict call to be bracketed by chrono clock measurements."
    )


def test_results_csv_exists_and_is_generated_by_executable():
    execute_pipeline()


def test_fold_specific_scaling_and_cv_mse_on_secret_data():
    rows = write_secret_dataset()
    expected = expected_cv_mses(rows)
    actual = execute_pipeline()

    for (alpha, observed_mse, time_us, mse_text), expected_mse in zip(actual, expected):
        assert abs(observed_mse - expected_mse) <= 0.00051, (
            f"Incorrect CV MSE for alpha {alpha}: got {mse_text}, expected "
            f"{expected_mse:.3f}. Scaling statistics must be learned from each "
            "training fold and applied to its validation fold."
        )
        assert time_us > 0, (
            f"Inference timing for alpha {alpha} was not a positive measured duration."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
