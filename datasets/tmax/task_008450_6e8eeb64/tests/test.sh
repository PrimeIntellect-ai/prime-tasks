#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import random
import subprocess
import pytest

HOME = "/home/user"
CSV_PATH = os.path.join(HOME, "sensor_data.csv")
JSON_PATH = os.path.join(HOME, "output", "metrics.json")
BINARY_PATH = "/tmp/pipeline_submission"


def run_command(command, cwd=HOME):
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
        check=False,
    )


def test_00_make_run_and_compile_pipeline():
    assert os.path.exists("/home/user/pipeline.go"), "The file /home/user/pipeline.go is missing."
    assert os.path.exists("/home/user/Makefile"), "The file /home/user/Makefile is missing."

    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = run_command(["make", "run"])
    assert result.returncode == 0, f"make run failed:\n{result.stdout}"
    assert os.path.isfile(JSON_PATH), "make run did not generate /home/user/output/metrics.json."

    result = run_command(["go", "build", "-o", BINARY_PATH, "/home/user/pipeline.go"])
    assert result.returncode == 0, f"pipeline.go did not compile:\n{result.stdout}"
    assert os.path.isfile(BINARY_PATH), "Compiling pipeline.go did not produce an executable."


def test_files_exist():
    assert os.path.exists("/home/user/pipeline.go"), "The file /home/user/pipeline.go is missing."
    assert os.path.exists("/home/user/Makefile"), "The file /home/user/Makefile is missing."
    assert os.path.exists("/home/user/output/metrics.json"), "The file /home/user/output/metrics.json is missing."


def compute_expected_metrics(csv_path=CSV_PATH):
    valid_rows = []

    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                a = float(row["sensor_A"])
                b = float(row["sensor_B"])
                c = float(row["sensor_C"])

                if 0.0 <= a <= 1000.0 and 0.0 <= b <= 1000.0 and 0.0 <= c <= 1000.0:
                    valid_rows.append({"A": a, "B": b, "C": c})
            except ValueError:
                continue

    n = len(valid_rows)
    assert n > 1, "Not enough valid rows to compute statistics."

    mean_a = sum(r["A"] for r in valid_rows) / n
    mean_b = sum(r["B"] for r in valid_rows) / n
    mean_c = sum(r["C"] for r in valid_rows) / n

    cov_ac = sum((r["A"] - mean_a) * (r["C"] - mean_c) for r in valid_rows) / (n - 1)
    cov_ab = sum((r["A"] - mean_a) * (r["B"] - mean_b) for r in valid_rows) / (n - 1)
    var_a = sum((r["A"] - mean_a) ** 2 for r in valid_rows) / (n - 1)
    var_b = sum((r["B"] - mean_b) ** 2 for r in valid_rows) / (n - 1)
    corr_ab = cov_ab / math.sqrt(var_a * var_b)

    return {
        "correlation_A_B": round(corr_ab, 4),
        "covariance_A_C": round(cov_ac, 4),
        "validation_status": "pass" if corr_ab >= 0.8 else "fail",
    }


def assert_metrics_match_expected():
    assert os.path.isfile(JSON_PATH), f"The file {JSON_PATH} was not generated."
    with open(JSON_PATH, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    expected_data = compute_expected_metrics()
    assert set(actual_data) == set(expected_data), "metrics.json must contain exactly the required fields."
    assert isinstance(actual_data["correlation_A_B"], float), "correlation_A_B must be a float."
    assert isinstance(actual_data["covariance_A_C"], float), "covariance_A_C must be a float."
    assert actual_data["correlation_A_B"] == expected_data["correlation_A_B"]
    assert actual_data["covariance_A_C"] == expected_data["covariance_A_C"]
    assert actual_data["validation_status"] == expected_data["validation_status"]


def test_metrics_json_content():
    with open(JSON_PATH, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    expected_data = compute_expected_metrics()

    assert "correlation_A_B" in actual_data, "Missing 'correlation_A_B' in JSON output."
    assert "covariance_A_C" in actual_data, "Missing 'covariance_A_C' in JSON output."
    assert "validation_status" in actual_data, "Missing 'validation_status' in JSON output."
    assert isinstance(actual_data["correlation_A_B"], float), "correlation_A_B must be a float."
    assert isinstance(actual_data["covariance_A_C"], float), "covariance_A_C must be a float."
    assert actual_data["correlation_A_B"] == expected_data["correlation_A_B"], f"Expected correlation_A_B to be {expected_data['correlation_A_B']}, got {actual_data['correlation_A_B']}"
    assert actual_data["covariance_A_C"] == expected_data["covariance_A_C"], f"Expected covariance_A_C to be {expected_data['covariance_A_C']}, got {actual_data['covariance_A_C']}"
    assert actual_data["validation_status"] == expected_data["validation_status"], f"Expected validation_status to be '{expected_data['validation_status']}', got '{actual_data['validation_status']}'"


def test_makefile_contains_run():
    makefile_path = "/home/user/Makefile"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "run:" in content, "Makefile does not contain a 'run' target."


def write_generated_dataset(strong_positive):
    rng = random.SystemRandom()
    values = rng.sample(range(15, 180), 9)
    rows = []
    for i, a in enumerate(values):
        b = 2 * a + 7 if strong_positive else 500 - 2 * a
        c = ((a * 7 + i * 13 + rng.randrange(1, 40)) % 240) + 20
        rows.append([f"2025-01-01T00:{i:02d}:00Z", a, b, c])
    rows.extend([
        ["bad-negative", -1, 25, 30],
        ["bad-high", 20, 1001, 30],
        ["bad-text", 20, 25, "invalid"],
    ])
    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "sensor_A", "sensor_B", "sensor_C"])
        writer.writerows(rows)


def test_pipeline_on_generated_inputs():
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    try:
        write_generated_dataset(True)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        result = run_command([BINARY_PATH])
        assert result.returncode == 0, f"Compiled pipeline failed on generated input:\n{result.stdout}"
        assert_metrics_match_expected()

        write_generated_dataset(False)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        result = run_command(["make", "run"])
        assert result.returncode == 0, f"make run failed on generated input:\n{result.stdout}"
        assert_metrics_match_expected()
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        run_command(["make", "run"])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
