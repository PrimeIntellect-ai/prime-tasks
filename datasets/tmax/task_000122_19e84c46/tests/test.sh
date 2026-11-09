#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import pytest


def kl_divergence(p, q):
    """Calculate KL divergence KL(P || Q)."""
    val = 0.0
    for p_i, q_i in zip(p, q):
        if p_i > 0:
            val += p_i * math.log(p_i / q_i)
    return val


def js_divergence(p, q):
    """Calculate JS divergence between P and Q."""
    m = [(p_i + q_i) / 2.0 for p_i, q_i in zip(p, q)]
    return 0.5 * kl_divergence(p, m) + 0.5 * kl_divergence(q, m)


@pytest.fixture
def input_data():
    input_path = "/home/user/latency_profiles.json"
    assert os.path.exists(input_path), f"Input file {input_path} is missing."
    with open(input_path, "r") as f:
        return json.load(f)


@pytest.fixture
def output_data():
    output_path = "/home/user/perf_report.json"
    assert os.path.exists(output_path), f"Output file {output_path} is missing. Did the Rust program run?"
    with open(output_path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_path} is not valid JSON.")


def test_rust_project_exists():
    """Verify that the Rust project directory, manifest, and Rust source exist."""
    project_dir = "/home/user/perf_analysis"
    cargo_toml = os.path.join(project_dir, "Cargo.toml")
    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} is missing."
    assert os.path.isfile(cargo_toml), f"Cargo.toml is missing in {project_dir}."
    rust_sources = []
    for root, _, files in os.walk(project_dir):
        rust_sources.extend(os.path.join(root, name) for name in files if name.endswith(".rs"))
    assert rust_sources, f"No Rust source files were found in {project_dir}."


def test_js_divergences(input_data, output_data):
    """Verify the Jensen-Shannon divergences."""
    assert "js_divergences" in output_data, "Missing 'js_divergences' in output JSON."

    version_a = input_data["version_a_histograms"]
    version_b = input_data["version_b_histograms"]

    expected_js = []
    for p, q in zip(version_a, version_b):
        expected_js.append(js_divergence(p, q))

    actual_js = output_data["js_divergences"]
    assert len(actual_js) == len(expected_js), "Incorrect number of JS divergences."

    for i, (actual, expected) in enumerate(zip(actual_js, expected_js)):
        assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-5), \
            f"JS divergence at index {i} is incorrect. Expected {expected}, got {actual}."


def test_expected_latencies(input_data, output_data):
    """Verify the expected latencies for Version B."""
    assert "version_b_expected_latencies" in output_data, "Missing 'version_b_expected_latencies' in output JSON."

    bin_centers = input_data["bin_centers"]
    version_b = input_data["version_b_histograms"]

    expected_latencies = []
    for hist in version_b:
        expected_val = sum(p * c for p, c in zip(hist, bin_centers))
        expected_latencies.append(expected_val)

    actual_latencies = output_data["version_b_expected_latencies"]
    assert len(actual_latencies) == len(expected_latencies), "Incorrect number of expected latencies."

    for i, (actual, expected) in enumerate(zip(actual_latencies, expected_latencies)):
        assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-5), \
            f"Expected latency at index {i} is incorrect. Expected {expected}, got {actual}."


def test_regression_coefficients(input_data, output_data):
    """Verify the polynomial regression coefficients using normal equations."""
    assert "regression_coefficients" in output_data, "Missing 'regression_coefficients' in output JSON."

    coeffs = output_data["regression_coefficients"]
    for key in ["a", "b", "c"]:
        assert key in coeffs, f"Missing coefficient '{key}' in regression_coefficients."

    a = coeffs["a"]
    b = coeffs["b"]
    c = coeffs["c"]

    x_vals = input_data["workload_sizes"]
    bin_centers = input_data["bin_centers"]
    version_b = input_data["version_b_histograms"]

    y_vals = [sum(p * bc for p, bc in zip(hist, bin_centers)) for hist in version_b]

    n = len(x_vals)
    sum_x = sum(x_vals)
    sum_x2 = sum(x**2 for x in x_vals)
    sum_x3 = sum(x**3 for x in x_vals)
    sum_x4 = sum(x**4 for x in x_vals)

    sum_y = sum(y_vals)
    sum_xy = sum(x * y for x, y in zip(x_vals, y_vals))
    sum_x2y = sum(x**2 * y for x, y in zip(x_vals, y_vals))

    eq1 = a * sum_x2 + b * sum_x + c * n
    eq2 = a * sum_x3 + b * sum_x2 + c * sum_x
    eq3 = a * sum_x4 + b * sum_x3 + c * sum_x2

    assert math.isclose(eq1, sum_y, rel_tol=1e-4, abs_tol=1e-4), \
        f"Regression coefficients do not satisfy the first normal equation. Expected {sum_y}, got {eq1}."
    assert math.isclose(eq2, sum_xy, rel_tol=1e-4, abs_tol=1e-4), \
        f"Regression coefficients do not satisfy the second normal equation. Expected {sum_xy}, got {eq2}."
    assert math.isclose(eq3, sum_x2y, rel_tol=1e-4, abs_tol=1e-4), \
        f"Regression coefficients do not satisfy the third normal equation. Expected {sum_x2y}, got {eq3}."
TEST_EOF

PROJECT=/home/user/perf_analysis
INPUT=/home/user/latency_profiles.json
OUTPUT=/home/user/perf_report.json
ORIGINAL=/tmp/latency_profiles.original.json
status=0

if ! cp "$INPUT" "$ORIGINAL"; then
    status=1
fi

run_and_test() {
    local before=/tmp/latency_profiles.before_run.json
    cp "$INPUT" "$before" || return 1
    rm -f "$OUTPUT"
    (cd "$PROJECT" && timeout 180s cargo run --quiet) || return 1
    cmp -s "$before" "$INPUT" || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

# Build and execute the submitted Rust project on the supplied data. Removing the
# report first ensures pytest can only inspect output produced by this execution.
if ! run_and_test; then
    status=1
fi

# Exercise the same executable on fresh, unanticipated normalized histograms so a
# program that merely emits the known report cannot pass.
if ! python3 - << 'PY'
import json
import random

rng = random.SystemRandom()

def histogram(force_zero):
    values = [rng.uniform(0.05, 2.0) for _ in range(5)]
    if force_zero:
        values[rng.randrange(5)] = 0.0
    total = sum(values)
    return [value / total for value in values]

data = {
    "workload_sizes": [5.0, 15.0, 25.0, 35.0, 45.0],
    "bin_centers": [0.75, 1.8, 3.25, 5.1, 7.6],
    "version_a_histograms": [histogram(i % 2 == 0) for i in range(5)],
    "version_b_histograms": [histogram(i % 2 == 1) for i in range(5)],
}
with open("/home/user/latency_profiles.json", "w") as f:
    json.dump(data, f)
PY
then
    status=1
elif ! run_and_test; then
    status=1
fi

# Restore the instructed input and rerun, leaving a verified report for it.
if ! cp "$ORIGINAL" "$INPUT"; then
    status=1
elif ! run_and_test; then
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
