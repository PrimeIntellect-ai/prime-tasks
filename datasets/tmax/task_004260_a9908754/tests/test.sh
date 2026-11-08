#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess

import pytest
import requests

PACKAGE = "/app/fastsim-2.0.0"
MAKEFILE = os.path.join(PACKAGE, "Makefile")
BINARY = os.path.join(PACKAGE, "bin/generate_data")
DATASET = "/home/user/dataset.csv"

_built_output = None
_truth_output = None


def build_and_run_submission():
    global _built_output
    if _built_output is not None:
        return _built_output

    assert os.path.isfile(MAKEFILE), f"The file {MAKEFILE} is missing."
    with open(MAKEFILE, "r") as f:
        content = f.read()
    assert "-ffast-math" not in content, "The Makefile still contains the -ffast-math flag. It must be removed to fix the Kahan summation."

    if os.path.lexists(BINARY):
        os.remove(BINARY)
    subprocess.run(["make", "clean"], cwd=PACKAGE, check=True, timeout=30)
    subprocess.run(["make"], cwd=PACKAGE, check=True, timeout=60)

    assert os.path.isfile(BINARY), "The build did not produce bin/generate_data."
    assert os.access(BINARY, os.X_OK), "bin/generate_data is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin/generate_data is not a compiled ELF executable."

    result = subprocess.run([BINARY, "500"], cwd=PACKAGE, capture_output=True, check=True, timeout=60)
    assert result.stderr == b"", f"generate_data wrote unexpected stderr: {result.stderr!r}"
    _built_output = result.stdout
    return _built_output


def generate_truth():
    global _truth_output
    if _truth_output is not None:
        return _truth_output

    truth_cpp = r'''#include <iostream>
#include <vector>
#include <cmath>
#include <iomanip>

int main(int argc, char** argv) {
    int n = 500;
    if (argc > 1) n = std::stoi(argv[1]);
    std::cout << "x,y\n";
    for(int i=0; i<n; ++i) {
        double x = i * 0.1;
        double sum = 0.0;
        double c = 0.0;
        for(int j=1; j<=10000; ++j) {
            double y_val = (std::sin(x + j) / (j * j)) - c;
            double t = sum + y_val;
            c = (t - sum) - y_val;
            sum = t;
        }
        double y = 2.5 * x + 1.2 + sum;
        std::cout << std::fixed << std::setprecision(8) << x << "," << y << "\n";
    }
    return 0;
}
'''
    with open("/tmp/truth_generator.cpp", "w") as f:
        f.write(truth_cpp)
    subprocess.run(["g++", "-O3", "-std=c++17", "/tmp/truth_generator.cpp", "-o", "/tmp/truth_generate_data"], check=True, timeout=60)
    result = subprocess.run(["/tmp/truth_generate_data", "500"], capture_output=True, check=True, timeout=60)
    _truth_output = result.stdout
    return _truth_output


def parse_csv(raw):
    text = raw.decode("utf-8")
    lines = text.splitlines()
    assert len(lines) == 501, f"Expected a header and 500 data rows, got {len(lines)} lines."
    assert lines[0] == "x,y", f"Expected CSV header 'x,y', got {lines[0]!r}."
    x_vals = []
    y_vals = []
    for row_number, line in enumerate(lines[1:], start=2):
        fields = line.split(",")
        assert len(fields) == 2, f"CSV row {row_number} does not have exactly two columns."
        try:
            x = float(fields[0])
            y = float(fields[1])
        except ValueError:
            pytest.fail(f"CSV row {row_number} contains a non-numeric value.")
        assert math.isfinite(x) and math.isfinite(y), f"CSV row {row_number} contains a non-finite value."
        x_vals.append(x)
        y_vals.append(y)
    return x_vals, y_vals


def expected_metrics(raw):
    x_vals, y_vals = parse_csv(raw)
    n = len(x_vals)
    mean_x = sum(x_vals) / n
    mean_y = sum(y_vals) / n
    cov_xy = sum((x - mean_x) * (y - mean_y) for x, y in zip(x_vals, y_vals)) / n
    var_x = sum((x - mean_x) ** 2 for x in x_vals) / n
    analytical_slope = cov_xy / var_x

    random.seed(42)
    slopes = []
    for _ in range(2000):
        indices = [random.randint(0, n - 1) for _ in range(n)]
        x_b = [x_vals[i] for i in indices]
        y_b = [y_vals[i] for i in indices]
        m_x = sum(x_b) / n
        m_y = sum(y_b) / n
        c_xy = sum((x - m_x) * (y - m_y) for x, y in zip(x_b, y_b)) / n
        v_x = sum((x - m_x) ** 2 for x in x_b) / n
        slopes.append(c_xy / v_x)
    slopes.sort()

    def percentile(values, p):
        k = (len(values) - 1) * (p / 100.0)
        lower = math.floor(k)
        upper = math.ceil(k)
        if lower == upper:
            return values[int(k)]
        return values[lower] * (upper - k) + values[upper] * (k - lower)

    return analytical_slope, percentile(slopes, 2.5), percentile(slopes, 97.5)


def test_makefile_fixed_and_package_recompiled():
    generated = build_and_run_submission()
    truth = generate_truth()
    assert generated == truth, "The rebuilt generate_data executable does not produce the reproducible Kahan-summation output."


def test_dataset_exists_and_matches_generated_data():
    assert os.path.isfile(DATASET), f"The dataset file {DATASET} is missing."
    with open(DATASET, "rb") as f:
        dataset = f.read()
    parse_csv(dataset)
    assert dataset == build_and_run_submission(), "dataset.csv was not generated by the rebuilt executable with argument 500."
    assert dataset == generate_truth(), "dataset.csv does not contain the expected reproducible simulation data."


def test_metrics_endpoint():
    try:
        response = requests.get("http://127.0.0.1:8000/metrics", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at 127.0.0.1:8000/metrics: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail("The response from /metrics is not valid JSON.")

    expected_keys = {"analytical_slope", "bootstrap_ci_lower", "bootstrap_ci_upper"}
    assert set(data.keys()) == expected_keys, f"Expected JSON keys {expected_keys}, got {set(data.keys())}"
    for key in expected_keys:
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), f"{key} must be a JSON number."
        assert math.isfinite(data[key]), f"{key} must be finite."

    with open(DATASET, "rb") as f:
        analytical_slope, ci_lower, ci_upper = expected_metrics(f.read())

    assert math.isclose(data["analytical_slope"], analytical_slope, rel_tol=1e-4, abs_tol=1e-4), f"Expected analytical_slope ~ {analytical_slope}, got {data['analytical_slope']}"
    assert math.isclose(data["bootstrap_ci_lower"], ci_lower, rel_tol=1e-4, abs_tol=1e-4), f"Expected bootstrap_ci_lower ~ {ci_lower}, got {data['bootstrap_ci_lower']}"
    assert math.isclose(data["bootstrap_ci_upper"], ci_upper, rel_tol=1e-4, abs_tol=1e-4), f"Expected bootstrap_ci_upper ~ {ci_upper}, got {data['bootstrap_ci_upper']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
