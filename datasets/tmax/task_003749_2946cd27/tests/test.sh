#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import re
import subprocess
import tempfile
import random
import pytest

PIPELINE = "/home/user/pipeline"
BUILD = os.path.join(PIPELINE, "build")
SOURCE = os.path.join(PIPELINE, "src", "processor.cpp")
EXECUTABLE = os.path.join(BUILD, "etl_pipeline")
OFFICIAL_STDOUT = "/tmp/etl_official_stdout.txt"


def get_sensor_data():
    data_path = "/home/user/data/sensor_data.csv"
    assert os.path.isfile(data_path), f"File missing: {data_path}"
    f1, f2 = [], []
    with open(data_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            f1.append(float(row['feature1']))
            f2.append(float(row['feature2']))
    return f1, f2


def calculate_pearson(x, y):
    n = len(x)
    if n == 0:
        return 0.0
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)
    if den_x == 0 or den_y == 0:
        return 0.0
    return num / math.sqrt(den_x * den_y)


def calculate_expanding_zscores(values):
    result = []
    for i, value in enumerate(values):
        if i == 0 or i == 1:
            result.append(0.0)
            continue
        window = values[:i]
        mean = sum(window) / len(window)
        variance = sum((x - mean) ** 2 for x in window) / (len(window) - 1)
        std_dev = math.sqrt(variance)
        result.append(0.0 if std_dev == 0.0 else (value - mean) / std_dev)
    return result


def calculate_expanding_zscore_predictions(f1):
    return [z * 0.5 + 1.2 for z in calculate_expanding_zscores(f1)]


def run_checked(command, **kwargs):
    result = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
        **kwargs,
    )
    assert result.returncode == 0, (
        f"Command failed: {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


@pytest.fixture(scope="session", autouse=True)
def build_and_execute_submission():
    assert os.path.isfile(SOURCE), f"Required source file missing: {SOURCE}"
    assert os.path.isfile(os.path.join(PIPELINE, "src", "main.cpp")), "main.cpp is missing"
    assert os.path.isfile(os.path.join(PIPELINE, "CMakeLists.txt")), "CMakeLists.txt is missing"

    os.makedirs(BUILD, exist_ok=True)
    run_checked(["cmake", ".."], cwd=BUILD)
    run_checked(["cmake", "--build", ".", "--clean-first"], cwd=BUILD)
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK), \
        "CMake did not produce an executable etl_pipeline"

    harness_source = r'''
#include <iomanip>
#include <iostream>
#include <vector>
#include "processor.h"

int main() {
    std::size_t n;
    if (!(std::cin >> n)) return 2;
    std::vector<double> x(n), y(n);
    for (double& value : x) std::cin >> value;
    for (double& value : y) std::cin >> value;
    std::vector<double> z = compute_zscore(x);
    std::cout << std::setprecision(17);
    for (std::size_t i = 0; i < z.size(); ++i) {
        if (i) std::cout << ' ';
        std::cout << z[i];
    }
    std::cout << "\n" << compute_pearson_correlation(x, y) << "\n";
    return 0;
}
'''
    harness_cpp = "/tmp/processor_harness.cpp"
    harness_bin = "/tmp/processor_harness"
    with open(harness_cpp, "w") as f:
        f.write(harness_source)
    run_checked([
        "g++", "-std=c++17", "-O2",
        "-I", os.path.join(PIPELINE, "src"),
        harness_cpp, SOURCE, "-o", harness_bin,
    ])

    rng = random.SystemRandom()
    random_x = [rng.uniform(-30.0, 30.0) + i * 0.37 for i in range(19)]
    random_y = [rng.uniform(-15.0, 15.0) - i * 0.21 for i in range(19)]
    cases = [
        ([4.0, 4.0, 4.0, 7.0, 2.0, 9.0], [1.0, 3.0, -2.0, 8.0, 5.0, 11.0]),
        ([-8.0, 2.5, 7.25, -1.5, 13.0, 3.0, 18.5], [9.0, -4.0, 2.0, 7.0, -3.0, 12.0, 1.0]),
        (random_x, random_y),
    ]

    for x, y in cases:
        payload = str(len(x)) + "\n" + " ".join(map(repr, x)) + "\n" + " ".join(map(repr, y)) + "\n"
        result = run_checked([harness_bin], input=payload)
        lines = result.stdout.strip().splitlines()
        assert len(lines) == 2, f"Unexpected processor harness output: {result.stdout!r}"
        actual_z = [float(value) for value in lines[0].split()]
        expected_z = calculate_expanding_zscores(x)
        assert len(actual_z) == len(expected_z)
        for i, (actual, expected) in enumerate(zip(actual_z, expected_z)):
            assert math.isfinite(actual), f"Non-finite Z-score at index {i}"
            assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9), \
                f"Incorrect expanding-window Z-score at index {i}: expected {expected}, got {actual}"
        actual_corr = float(lines[1])
        expected_corr = calculate_pearson(x, y)
        assert math.isfinite(actual_corr), "Pearson correlation is not finite"
        assert math.isclose(actual_corr, expected_corr, rel_tol=1e-9, abs_tol=1e-9), \
            f"Incorrect Pearson correlation: expected {expected_corr}, got {actual_corr}"

    with tempfile.TemporaryDirectory() as temp_dir:
        dynamic_csv = os.path.join(temp_dir, "dynamic_sensor_data.csv")
        x, y = random_x, random_y
        with open(dynamic_csv, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["feature1", "feature2"])
            writer.writerows(zip(x, y))

        result = run_checked([EXECUTABLE, dynamic_csv], cwd=temp_dir)
        expected_corr_text = f"{calculate_pearson(x, y):.4f}"
        assert f"Pearson Correlation: {expected_corr_text}" in result.stdout, \
            f"Executable printed the wrong correlation: {result.stdout!r}"

        generated = os.path.join(temp_dir, "predictions.csv")
        assert os.path.isfile(generated), "Running etl_pipeline did not generate predictions.csv"
        with open(generated, "r") as f:
            rows = list(csv.DictReader(f))
        expected_preds = calculate_expanding_zscore_predictions(x)
        assert len(rows) == len(expected_preds)
        for i, (row, expected) in enumerate(zip(rows, expected_preds)):
            assert row["id"] == str(i), f"Incorrect prediction id at row {i}"
            actual = float(row["pred"])
            assert math.isclose(actual, round(expected, 4), abs_tol=1e-3), \
                f"Dynamic pipeline prediction mismatch at index {i}: expected {expected:.4f}, got {actual}"

    official = run_checked([EXECUTABLE, "/home/user/data/sensor_data.csv"], cwd=BUILD)
    with open(OFFICIAL_STDOUT, "w") as f:
        f.write(official.stdout)


def test_experiment_log():
    log_path = "/home/user/experiment_log.json"
    assert os.path.isfile(log_path), f"Experiment log missing: {log_path}"

    with open(log_path, 'r') as f:
        try:
            log_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Experiment log {log_path} is not valid JSON.")

    assert "experiment_name" in log_data, "Missing 'experiment_name' in experiment log."
    assert log_data["experiment_name"] == "fix_data_leakage", "Incorrect 'experiment_name'."

    assert "pearson_correlation_feature1_feature2" in log_data, "Missing 'pearson_correlation_feature1_feature2' in experiment log."

    f1, f2 = get_sensor_data()
    expected_corr = calculate_pearson(f1, f2)
    expected_corr_rounded = round(expected_corr, 4)

    actual_corr = log_data["pearson_correlation_feature1_feature2"]
    assert isinstance(actual_corr, float), "Pearson correlation value should be a float."
    assert math.isclose(actual_corr, expected_corr_rounded, abs_tol=1e-4), \
        f"Expected Pearson correlation ~{expected_corr_rounded}, but got {actual_corr}"

    with open(OFFICIAL_STDOUT, "r") as f:
        stdout = f.read()
    match = re.search(r"Pearson Correlation:\s*(-?\d+\.\d{4})", stdout)
    assert match, f"Pipeline did not print a correlation to four decimal places: {stdout!r}"
    assert math.isclose(actual_corr, float(match.group(1)), abs_tol=1e-12), \
        "Experiment log does not contain the exact correlation value printed by the pipeline."


def test_predictions_csv():
    preds_path = "/home/user/pipeline/build/predictions.csv"
    assert os.path.isfile(preds_path), f"Predictions CSV missing: {preds_path}. Did you build and run the pipeline?"

    f1, _ = get_sensor_data()
    expected_preds = calculate_expanding_zscore_predictions(f1)

    actual_preds = []
    with open(preds_path, 'r') as f:
        reader = csv.DictReader(f)
        assert "id" in reader.fieldnames and "pred" in reader.fieldnames, "predictions.csv header is incorrect."
        for row in reader:
            actual_preds.append(float(row['pred']))

    assert len(actual_preds) == len(expected_preds), f"Expected {len(expected_preds)} predictions, found {len(actual_preds)}"

    for i, (actual, expected) in enumerate(zip(actual_preds, expected_preds)):
        expected_rounded = round(expected, 4)
        assert math.isclose(actual, expected_rounded, abs_tol=1e-3), \
            f"Prediction mismatch at index {i}: Expected ~{expected_rounded}, got {actual}. Check expanding window logic."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
