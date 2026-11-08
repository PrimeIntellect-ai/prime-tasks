#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import statistics
import subprocess
import shutil
import pytest

RAW_DATA_PATH = "/home/user/raw_profiling.txt"
PROJECT_PATH = "/home/user/profiler"
MANIFEST_PATH = os.path.join(PROJECT_PATH, "Cargo.toml")
CSV_PATH = "/home/user/reshaped_data.csv"
JSON_PATH = "/home/user/profiling_report.json"


def compute_expected_data():
    """Reads raw data and computes expected CSV rows and t-test statistics."""
    expected_csv = []
    algo_a_times = []
    algo_b_times = []

    with open(RAW_DATA_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            run_id, algo, target, primer, time_ns = parts
            time_ns = float(time_ns)

            match_score = sum(1 for t, p in zip(target, primer) if t == p)
            expected_csv.append((run_id, algo, str(match_score), str(int(time_ns))))

            if algo == "AlgoA":
                algo_a_times.append(time_ns)
            elif algo == "AlgoB":
                algo_b_times.append(time_ns)

    n_a = len(algo_a_times)
    n_b = len(algo_b_times)
    mean_a = statistics.mean(algo_a_times)
    mean_b = statistics.mean(algo_b_times)
    var_a = statistics.variance(algo_a_times)
    var_b = statistics.variance(algo_b_times)
    se_a = var_a / n_a
    se_b = var_b / n_b
    t_stat = (mean_a - mean_b) / math.sqrt(se_a + se_b)
    df_num = (se_a + se_b) ** 2
    df_den = (se_a ** 2 / (n_a - 1)) + (se_b ** 2 / (n_b - 1))
    df = df_num / df_den

    return expected_csv, mean_a, mean_b, t_stat, df


def beta_continued_fraction(a, b, x):
    max_iterations = 200
    epsilon = 3.0e-14
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

    for m in range(1, max_iterations + 1):
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
        if abs(delta - 1.0) < epsilon:
            return h

    raise AssertionError("Incomplete beta calculation did not converge")


def regularized_incomplete_beta(a, b, x):
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    factor = math.exp(
        math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
        + a * math.log(x) + b * math.log1p(-x)
    )
    if x < (a + 1.0) / (a + b + 2.0):
        return factor * beta_continued_fraction(a, b, x) / a
    return 1.0 - factor * beta_continued_fraction(b, a, 1.0 - x) / b


def two_tailed_student_t_p_value(t_stat, df):
    x = df / (df + t_stat * t_stat)
    return regularized_incomplete_beta(df / 2.0, 0.5, x)


def test_00_rust_project_compiles_runs_and_generates_outputs():
    assert os.path.isdir(PROJECT_PATH), f"Rust project not found at {PROJECT_PATH}"
    assert os.path.isfile(MANIFEST_PATH), f"Cargo.toml not found at {MANIFEST_PATH}"

    rust_sources = []
    for root, dirs, files in os.walk(PROJECT_PATH):
        dirs[:] = [d for d in dirs if d != "target"]
        for name in files:
            if name.endswith(".rs"):
                path = os.path.join(root, name)
                if os.path.isfile(path) and os.path.getsize(path) > 0:
                    rust_sources.append(path)
    assert rust_sources, "The profiler project contains no non-empty Rust source files"

    for output in (CSV_PATH, JSON_PATH):
        if os.path.isdir(output) and not os.path.islink(output):
            shutil.rmtree(output)
        elif os.path.lexists(output):
            os.remove(output)

    target_dir = "/tmp/verifier_profiler_target"
    shutil.rmtree(target_dir, ignore_errors=True)
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = target_dir

    try:
        result = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", MANIFEST_PATH],
            cwd=PROJECT_PATH,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=240,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Rust profiler did not compile and run within 240 seconds")

    assert result.returncode == 0, (
        "Rust profiler failed to compile or run cleanly.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(CSV_PATH), "Running the Rust profiler did not produce reshaped_data.csv"
    assert os.path.isfile(JSON_PATH), "Running the Rust profiler did not produce profiling_report.json"


def test_reshaped_data_csv():
    """Validates the reshaped CSV file contents."""
    assert os.path.isfile(CSV_PATH), f"Reshaped CSV file not found at {CSV_PATH}"

    expected_csv, _, _, _, _ = compute_expected_data()

    with open(CSV_PATH, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."

    header = rows[0]
    expected_header = ["run_id", "algorithm", "match_score", "time_ns"]
    assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_csv), f"Expected {len(expected_csv)} data rows, got {len(data_rows)}"

    expected_csv_sorted = sorted(expected_csv, key=lambda x: x[0])
    data_rows_sorted = sorted(data_rows, key=lambda x: x[0])

    for expected, actual in zip(expected_csv_sorted, data_rows_sorted):
        assert actual == list(expected), f"CSV row mismatch. Expected {expected}, got {actual}"


def test_profiling_report_json():
    """Validates the profiling report JSON file contents."""
    assert os.path.isfile(JSON_PATH), f"Profiling report JSON not found at {JSON_PATH}"

    with open(JSON_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {JSON_PATH} is not valid JSON.")

    expected_keys = {"algo_a_mean", "algo_b_mean", "t_statistic", "degrees_of_freedom", "p_value", "significant_at_05"}
    assert set(report.keys()) == expected_keys, f"JSON keys mismatch. Expected {expected_keys}, got {set(report.keys())}"

    _, mean_a, mean_b, t_stat, df = compute_expected_data()

    assert math.isclose(report["algo_a_mean"], mean_a, rel_tol=1e-3), f"algo_a_mean mismatch. Expected ~{mean_a}, got {report['algo_a_mean']}"
    assert math.isclose(report["algo_b_mean"], mean_b, rel_tol=1e-3), f"algo_b_mean mismatch. Expected ~{mean_b}, got {report['algo_b_mean']}"
    assert math.isclose(abs(report["t_statistic"]), abs(t_stat), rel_tol=1e-3), f"t_statistic mismatch. Expected ~{t_stat}, got {report['t_statistic']}"
    assert math.isclose(report["degrees_of_freedom"], df, rel_tol=1e-3), f"degrees_of_freedom mismatch. Expected ~{df}, got {report['degrees_of_freedom']}"

    p_value = report["p_value"]
    assert 0.01 < p_value < 0.02, f"p_value out of expected range (0.01 - 0.02). Got {p_value}"
    expected_p_value = two_tailed_student_t_p_value(t_stat, df)
    assert math.isclose(p_value, expected_p_value, rel_tol=1e-3, abs_tol=1e-3), f"p_value mismatch. Expected ~{expected_p_value}, got {p_value}"

    assert report["significant_at_05"] is True, "significant_at_05 should be true since p_value < 0.05"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
