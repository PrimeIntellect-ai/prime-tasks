#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/sensor_etl")
CSV_PATH = Path("/home/user/data/sensors.csv")
RESULTS_PATH = Path("/home/user/results.json")
CARGO_ENV = {
    **os.environ,
    "HOME": "/home/user",
    "CARGO_HOME": "/home/user/.cargo",
    "PATH": "/home/user/.cargo/bin:/root/.cargo/bin:" + os.environ.get("PATH", ""),
}


def compute_expected_metrics(csv_path):
    processed_rows = 0
    temp_ratios = []
    x_vals = []
    y_vals = []

    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            status = row["status"].strip()
            if status == "OK":
                processed_rows += 1
                temp = float(row["temperature"])
                hum = float(row["humidity"])
                temp_ratios.append(temp / hum)
                x_vals.append(temp)
                y_vals.append(hum)

    if processed_rows == 0:
        return 0, 0.0, 0.0, 0.0

    avg_temp_ratio = sum(temp_ratios) / processed_rows
    mean_x = sum(x_vals) / processed_rows
    mean_y = sum(y_vals) / processed_rows
    cov = sum((x - mean_x) * (y - mean_y) for x, y in zip(x_vals, y_vals))
    var = sum((x - mean_x) ** 2 for x in x_vals)
    slope = cov / var if var != 0 else 0.0
    intercept = mean_y - slope * mean_x
    return processed_rows, avg_temp_ratio, slope, intercept


@pytest.fixture(autouse=True)
def restore_input():
    original = CSV_PATH.read_bytes()
    try:
        yield
    finally:
        CSV_PATH.write_bytes(original)


def run_pipeline():
    if RESULTS_PATH.exists():
        RESULTS_PATH.unlink()

    completed = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT / "Cargo.toml")],
        cwd=PROJECT,
        env=CARGO_ENV,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert completed.returncode == 0, "Cargo build/run failed:\n" + completed.stdout
    assert RESULTS_PATH.is_file(), "The executed Rust pipeline did not create /home/user/results.json"


def assert_results_match(csv_path):
    with open(RESULTS_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")

    expected_rows, expected_avg_ratio, expected_slope, expected_intercept = compute_expected_metrics(csv_path)

    assert "processed_rows" in results, "Missing 'processed_rows' in results.json"
    assert "average_temp_ratio" in results, "Missing 'average_temp_ratio' in results.json"
    assert "model_slope" in results, "Missing 'model_slope' in results.json"
    assert "model_intercept" in results, "Missing 'model_intercept' in results.json"

    assert results["processed_rows"] == expected_rows, f"processed_rows is incorrect. Expected {expected_rows}, got {results['processed_rows']}"
    assert results["average_temp_ratio"] == pytest.approx(expected_avg_ratio, rel=1e-3, abs=1e-4), f"average_temp_ratio is incorrect. Expected approx {expected_avg_ratio}, got {results['average_temp_ratio']}"
    assert results["model_slope"] == pytest.approx(expected_slope, rel=1e-3, abs=1e-4), f"model_slope is incorrect. Expected approx {expected_slope}, got {results['model_slope']}"
    assert results["model_intercept"] == pytest.approx(expected_intercept, rel=1e-3, abs=1e-4), f"model_intercept is incorrect. Expected approx {expected_intercept}, got {results['model_intercept']}"


def test_results_json_exists_and_correct():
    results_path = "/home/user/results.json"
    csv_path = "/home/user/data/sensors.csv"

    assert PROJECT.joinpath("src/main.rs").is_file(), "Expected Rust entry point src/main.rs does not exist."
    assert os.path.exists(csv_path), f"Expected data file at {csv_path} does not exist."

    run_pipeline()
    assert os.path.exists(results_path), f"Expected results file at {results_path} does not exist."
    assert_results_match(csv_path)


def test_pipeline_recomputes_metrics_for_runtime_input():
    rng = secrets.SystemRandom()
    rows = []
    valid_statuses = [" OK", "OK ", "  OK  ", "\tOK\t"]

    for i in range(7):
        temperature = round(rng.uniform(8.0, 42.0) + i * 0.37, 6)
        humidity = round(rng.uniform(25.0, 85.0) + i * 0.53, 6)
        rows.append([i + 1, temperature, humidity, valid_statuses[i % len(valid_statuses)]])

    rows.extend([
        [101, round(rng.uniform(10.0, 40.0), 6), round(rng.uniform(30.0, 80.0), 6), "ERROR"],
        [102, round(rng.uniform(10.0, 40.0), 6), round(rng.uniform(30.0, 80.0), 6), "ok"],
        [103, round(rng.uniform(10.0, 40.0), 6), round(rng.uniform(30.0, 80.0), 6), " FAIL "],
    ])

    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "temperature", "humidity", "status"])
        writer.writerows(rows)

    run_pipeline()
    assert_results_match(CSV_PATH)


def test_cargo_toml_dependencies():
    cargo_toml_path = "/home/user/sensor_etl/Cargo.toml"
    assert os.path.exists(cargo_toml_path), f"Expected Cargo.toml at {cargo_toml_path} does not exist."

    with open(cargo_toml_path, "r") as f:
        content = f.read()

    assert "linreg" in content, "The 'linreg' crate is missing from Cargo.toml dependencies."

    completed = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", cargo_toml_path],
        cwd=PROJECT,
        env=CARGO_ENV,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert completed.returncode == 0, "Cargo.toml is not a valid Cargo manifest: " + completed.stderr
    metadata = json.loads(completed.stdout)
    package = next((p for p in metadata["packages"] if p["name"] == "sensor_etl"), None)
    assert package is not None, "Cargo metadata does not contain the sensor_etl package."
    assert any(dep["name"] == "linreg" for dep in package["dependencies"]), "linreg is not declared as a Cargo dependency."
    assert any("bin" in target["kind"] for target in package["targets"]), "sensor_etl has no Rust binary target to execute."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
