#!/bin/bash
set -o pipefail
mkdir -p /logs/verifier

export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/cargo
export PATH=/opt/cargo/bin:$PATH

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import pytest

def test_rust_project_directory_exists():
    """Verify that the Rust project directory was initialized."""
    project_dir = "/home/user/performance_analysis"
    assert os.path.isdir(project_dir), f"Expected Rust project directory at {project_dir} does not exist."

def test_analysis_results_file_exists():
    """Verify that the analysis_results.json file was created."""
    results_file = "/home/user/analysis_results.json"
    assert os.path.isfile(results_file), f"Expected output file at {results_file} does not exist."

def test_analysis_results_content():
    """Verify the contents and computed statistics in analysis_results.json."""
    results_file = "/home/user/analysis_results.json"

    with open(results_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {results_file} does not contain valid JSON.")

    required_keys = ["mean_latency_A", "mean_latency_B", "t_stat", "p_value", "correlation"]
    for key in required_keys:
        assert key in data, f"Missing required key '{key}' in {results_file}."

    # Recomputed expected values based on the dataset
    expected_mean_A = 120.0
    expected_mean_B = 90.0
    expected_t_stat = 6.0
    expected_p_value = 0.0003314
    expected_correlation = 0.9856

    assert math.isclose(data["mean_latency_A"], expected_mean_A, rel_tol=1e-3), \
        f"Expected mean_latency_A to be ~{expected_mean_A}, got {data['mean_latency_A']}"

    assert math.isclose(data["mean_latency_B"], expected_mean_B, rel_tol=1e-3), \
        f"Expected mean_latency_B to be ~{expected_mean_B}, got {data['mean_latency_B']}"

    assert math.isclose(abs(data["t_stat"]), expected_t_stat, rel_tol=1e-2), \
        f"Expected absolute t_stat to be ~{expected_t_stat}, got {data['t_stat']}"

    assert math.isclose(data["p_value"], expected_p_value, rel_tol=1e-1), \
        f"Expected p_value to be ~{expected_p_value}, got {data['p_value']}"

    assert math.isclose(data["correlation"], expected_correlation, rel_tol=1e-2), \
        f"Expected correlation to be ~{expected_correlation}, got {data['correlation']}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_results.py
import csv
import json
import math
import os

CSV_PATH = "/home/user/system_metrics.csv"
RESULTS_PATH = "/home/user/analysis_results.json"
KEYS = ["mean_latency_A", "mean_latency_B", "t_stat", "p_value", "correlation"]


def betacf(a, b, x):
    max_iter = 300
    eps = 3.0e-14
    fpmin = 1.0e-300
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < fpmin:
        d = fpmin
    d = 1.0 / d
    h = d
    for m in range(1, max_iter + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < fpmin:
            d = fpmin
        c = 1.0 + aa / c
        if abs(c) < fpmin:
            c = fpmin
        d = 1.0 / d
        h *= d * c

        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < fpmin:
            d = fpmin
        c = 1.0 + aa / c
        if abs(c) < fpmin:
            c = fpmin
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < eps:
            return h
    raise AssertionError("Incomplete beta calculation did not converge")


def regularized_beta(x, a, b):
    if not 0.0 <= x <= 1.0:
        raise AssertionError("Invalid beta argument")
    if x == 0.0:
        return 0.0
    if x == 1.0:
        return 1.0
    bt = math.exp(
        math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
        + a * math.log(x) + b * math.log1p(-x)
    )
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * betacf(a, b, x) / a
    return 1.0 - bt * betacf(b, a, 1.0 - x) / b


with open(CSV_PATH, newline="") as f:
    rows = list(csv.DictReader(f))

lat_a = [float(r["latency_ms"]) for r in rows if r["config"] == "A"]
lat_b = [float(r["latency_ms"]) for r in rows if r["config"] == "B"]
assert len(lat_a) >= 2 and len(lat_b) >= 2

mean_a = sum(lat_a) / len(lat_a)
mean_b = sum(lat_b) / len(lat_b)
var_a = sum((x - mean_a) ** 2 for x in lat_a) / (len(lat_a) - 1)
var_b = sum((x - mean_b) ** 2 for x in lat_b) / (len(lat_b) - 1)
term_a = var_a / len(lat_a)
term_b = var_b / len(lat_b)
t_stat = (mean_a - mean_b) / math.sqrt(term_a + term_b)
df = (term_a + term_b) ** 2 / (
    term_a ** 2 / (len(lat_a) - 1) + term_b ** 2 / (len(lat_b) - 1)
)
p_value = regularized_beta(df / (df + t_stat * t_stat), df / 2.0, 0.5)

pressure = [float(r["cpu_util"]) * float(r["mem_util"]) for r in rows]
latency = [float(r["latency_ms"]) for r in rows]
mean_p = sum(pressure) / len(pressure)
mean_l = sum(latency) / len(latency)
correlation = sum((x - mean_p) * (y - mean_l) for x, y in zip(pressure, latency)) / math.sqrt(
    sum((x - mean_p) ** 2 for x in pressure) *
    sum((y - mean_l) ** 2 for y in latency)
)

assert os.path.isfile(RESULTS_PATH), "The Rust program did not create analysis_results.json"
with open(RESULTS_PATH) as f:
    data = json.load(f)

for key in KEYS:
    assert key in data, f"Missing required key {key}"
    assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), f"{key} must be numeric"
    assert math.isfinite(float(data[key])), f"{key} must be finite"

assert math.isclose(float(data["mean_latency_A"]), mean_a, rel_tol=1e-5, abs_tol=5e-4)
assert math.isclose(float(data["mean_latency_B"]), mean_b, rel_tol=1e-5, abs_tol=5e-4)
assert math.isclose(abs(float(data["t_stat"])), abs(t_stat), rel_tol=1e-4, abs_tol=5e-4)
assert math.isclose(float(data["p_value"]), p_value, rel_tol=1e-3, abs_tol=5e-4)
assert math.isclose(float(data["correlation"]), correlation, rel_tol=1e-4, abs_tol=5e-4)
DYNAMIC_EOF

run_verification() {
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    test -f /home/user/performance_analysis/Cargo.toml || return 1
    test -s /home/user/performance_analysis/src/main.rs || return 1
    test -x /opt/cargo/bin/cargo || return 1

    cp /home/user/system_metrics.csv /tmp/system_metrics.original.csv || return 1
    cat << 'CSV_EOF' > /home/user/system_metrics.csv
config,cpu_util,mem_util,latency_ms
A,10.0,20.0,30.0
A,20.0,15.0,45.0
A,30.0,25.0,40.0
A,40.0,20.0,55.0
A,50.0,30.0,50.0
B,15.0,10.0,28.0
B,25.0,20.0,35.0
B,35.0,15.0,33.0
B,45.0,25.0,42.0
B,55.0,20.0,39.0
CSV_EOF

    rm -f /home/user/analysis_results.json
    if ! (cd /home/user/performance_analysis && timeout 180 cargo run --release --quiet); then
        cp /tmp/system_metrics.original.csv /home/user/system_metrics.csv
        return 1
    fi

    if ! python3 /tmp/test_dynamic_results.py; then
        cp /tmp/system_metrics.original.csv /home/user/system_metrics.csv
        return 1
    fi

    cp /tmp/system_metrics.original.csv /home/user/system_metrics.csv || return 1
    rm -f /home/user/analysis_results.json
    (cd /home/user/performance_analysis && timeout 180 cargo run --release --quiet) || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if run_verification 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
