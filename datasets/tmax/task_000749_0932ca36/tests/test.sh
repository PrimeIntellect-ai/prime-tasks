#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import stat
import subprocess

import pytest

ANALYSIS_DIR = "/home/user/analysis"
SALES_PATH = "/home/user/sales.csv"
RESULT_PATH = "/home/user/regression_results.json"

CANONICAL_CSV = '''sqft,price
1500,310000
2000,390000
invalid,500000
1200,250000
1800,"360,000"
2500,510000
1600,310000
2100,
  1750  ,  350000  
'''


def assert_regular_file(path):
    assert os.path.exists(path), f"Required file {path} is missing."
    assert not os.path.islink(path), f"Required file {path} must not be a symbolic link."
    assert stat.S_ISREG(os.stat(path).st_mode), f"Required path {path} is not a regular file."


def run_go_program():
    if os.path.lexists(RESULT_PATH):
        os.remove(RESULT_PATH)

    completed = subprocess.run(
        ["go", "run", "."],
        cwd=ANALYSIS_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        "The Go program failed when executed with `go run .`.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert_regular_file(RESULT_PATH)


def load_results():
    with open(RESULT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT_PATH} does not contain valid JSON.")


@pytest.fixture(scope="session", autouse=True)
def execute_submission_on_original_input():
    assert os.path.isdir(ANALYSIS_DIR), f"Expected analysis directory {ANALYSIS_DIR} is missing."
    assert not os.path.islink(ANALYSIS_DIR), f"{ANALYSIS_DIR} must be a real directory."
    assert_regular_file(os.path.join(ANALYSIS_DIR, "go.mod"))
    assert_regular_file(os.path.join(ANALYSIS_DIR, "main.go"))

    with open(SALES_PATH, "w", newline="") as f:
        f.write(CANONICAL_CSV)
    run_go_program()


def test_regression_results_exists():
    file_path = "/home/user/regression_results.json"
    assert os.path.isfile(file_path), f"Expected output file {file_path} is missing. Did the Go program run and generate it?"


def test_regression_results_content():
    file_path = "/home/user/regression_results.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    data = load_results()

    required_keys = {"valid_count", "slope", "intercept", "slope_std_error"}
    missing_keys = required_keys - set(data.keys())
    assert not missing_keys, f"JSON output is missing required keys: {missing_keys}"

    assert data["valid_count"] == 6, f"Expected valid_count to be 6, but got {data['valid_count']}. Make sure you are dropping rows that fail to parse as standard 64-bit floats."

    expected_slope = 193.6496699669967
    assert math.isclose(data["slope"], expected_slope, rel_tol=1e-3), \
        f"Expected slope to be close to {expected_slope}, but got {data['slope']}."

    expected_intercept = 12831.68316831671
    assert math.isclose(data["intercept"], expected_intercept, rel_tol=1e-3), \
        f"Expected intercept to be close to {expected_intercept}, but got {data['intercept']}."

    expected_std_error = 11.167374
    assert math.isclose(data["slope_std_error"], expected_std_error, rel_tol=1e-3), \
        f"Expected slope_std_error to be close to {expected_std_error}, but got {data['slope_std_error']}."


def test_go_program_on_unseen_data_with_invalid_rows():
    rng = random.SystemRandom()
    count = rng.randint(7, 11)
    true_slope = rng.uniform(25.0, 350.0)
    true_intercept = rng.uniform(-50000.0, 80000.0)

    valid_rows = []
    parsed_points = []
    for i in range(count):
        x = rng.uniform(400.0, 5000.0) + i * 37.0
        y = true_intercept + true_slope * x + rng.uniform(-25000.0, 25000.0)
        if i == 0:
            x_text = f"  {x:.6e}  "
            y_text = f"  {y:.6e}  "
        else:
            x_text = f"{x:.6f}"
            y_text = f"{y:.6f}"
        valid_rows.append([x_text, y_text])
        parsed_points.append((float(x_text.strip()), float(y_text.strip())))

    invalid_rows = [
        ["not-a-number", "123000"],
        ["1,234", "500000"],
        ["900", "$123000"],
        ["", "400000"],
        ["1100", ""],
        ["1000", "3 000"],
    ]
    rows = valid_rows + invalid_rows
    rng.shuffle(rows)

    with open(SALES_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["sqft", "price"])
        writer.writerows(rows)

    xs = [point[0] for point in parsed_points]
    ys = [point[1] for point in parsed_points]
    x_mean = sum(xs) / count
    y_mean = sum(ys) / count
    sxx = sum((x - x_mean) ** 2 for x in xs)
    slope = sum((x - x_mean) * (y - y_mean) for x, y in parsed_points) / sxx
    intercept = y_mean - slope * x_mean
    residual_sse = sum((y - (intercept + slope * x)) ** 2 for x, y in parsed_points)
    slope_std_error = math.sqrt((residual_sse / (count - 2)) / sxx)

    run_go_program()
    data = load_results()
    required_keys = {"valid_count", "slope", "intercept", "slope_std_error"}
    assert required_keys <= set(data), f"JSON output is missing required keys: {required_keys - set(data)}"
    assert data["valid_count"] == count, "Rows that do not parse directly as floats were not dropped correctly."
    assert math.isclose(data["slope"], slope, rel_tol=1e-8, abs_tol=1e-8)
    assert math.isclose(data["intercept"], intercept, rel_tol=1e-8, abs_tol=1e-6)
    assert math.isclose(data["slope_std_error"], slope_std_error, rel_tol=1e-8, abs_tol=1e-8)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
