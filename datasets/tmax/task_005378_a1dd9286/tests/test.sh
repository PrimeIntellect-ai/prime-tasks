#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import subprocess

import numpy as np
import pandas as pd
import pytest

METRICS = "/home/user/metrics.csv"
ANALYSIS = "/home/user/analysis.json"
PROFILE = "/home/user/profile.sh"
EXPECTED_KEYS = {
    "total_cpu_integral",
    "max_latency_derivative",
    "poly_a",
    "poly_b",
    "poly_c",
}
CANONICAL_ROWS = np.array([
    [0.0, 10.0, 15.0, 20.0],
    [1.0, 20.0, 35.0, 30.0],
    [2.0, 30.0, 65.0, 45.0],
    [3.0, 40.0, 105.0, 65.0],
    [4.0, 50.0, 155.0, 90.0],
    [5.0, 60.0, 215.0, 120.0],
])
COLUMNS = ["Time_s", "Requests_Per_Sec", "Latency_ms", "CPU_util"]


def run_as_user(command, timeout=30):
    result = subprocess.run(
        ["runuser", "-u", "user", "--"] + command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed ({' '.join(command)}):\n{result.stdout}"
    )
    return result.stdout


def read_config():
    values = {}
    assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$")
    with open("/app/config.env", "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            match = assignment.fullmatch(line)
            assert match, f"Invalid line in /app/config.env: {raw_line.rstrip()}"
            key, value = match.groups()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1]
            values[key] = value
    return values


def assert_configured():
    values = read_config()
    assert values.get("REDIS_HOST") == "127.0.0.1"
    assert values.get("REDIS_PORT") == "6379"
    assert values.get("WEB_API_URL") == "http://127.0.0.1:5000"


def read_metrics():
    try:
        df = pd.read_csv(METRICS)
    except Exception as exc:
        pytest.fail(f"Failed to read {METRICS}: {exc}")
    assert list(df.columns) == COLUMNS, f"Unexpected metrics columns: {list(df.columns)}"
    assert len(df) >= 3, "metrics.csv must contain at least three data rows"
    for column in COLUMNS:
        assert pd.api.types.is_numeric_dtype(df[column]), f"Column {column} must be numeric"
        assert np.isfinite(df[column].to_numpy(dtype=float)).all(), f"Column {column} contains non-finite data"
    return df


def expected_values(df):
    time = df["Time_s"].to_numpy(dtype=float)
    req = df["Requests_Per_Sec"].to_numpy(dtype=float)
    lat = df["Latency_ms"].to_numpy(dtype=float)
    cpu = df["CPU_util"].to_numpy(dtype=float)
    dt = np.diff(time)
    assert np.all(dt != 0), "Time_s contains duplicate adjacent values"
    derivs = np.diff(lat) / dt
    coeffs = np.polyfit(req, lat, 2)
    return {
        "total_cpu_integral": float(np.trapz(cpu, time)),
        "max_latency_derivative": float(np.nanmax(derivs)),
        "poly_a": float(coeffs[0]),
        "poly_b": float(coeffs[1]),
        "poly_c": float(coeffs[2]),
    }


def check_analysis(expected):
    try:
        with open(ANALYSIS, "r", encoding="utf-8") as f:
            data = json.load(f, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    except Exception as exc:
        pytest.fail(f"Failed to read or parse {ANALYSIS}: {exc}")

    assert set(data) == EXPECTED_KEYS, (
        f"analysis.json must contain exactly {sorted(EXPECTED_KEYS)}; got {sorted(data)}"
    )
    max_error = 0.0
    threshold = 0.01
    for key, expected_value in expected.items():
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), (
            f"Value for {key} must be a number, got {type(value)}"
        )
        assert math.isfinite(float(value)), f"Value for {key} must be finite"
        error = abs(float(value) - expected_value)
        max_error = max(max_error, error)
        assert error <= threshold, (
            f"Mismatch for {key}. Expected ~{expected_value:.5f}, got {value}. "
            f"Absolute error: {error:.5f} (Threshold: <= {threshold})"
        )
    print(f"All metrics within threshold. Maximum absolute error: {max_error:.5f}")


def execute_profile_and_check(df):
    before = open(METRICS, "rb").read()
    if os.path.lexists(ANALYSIS):
        os.remove(ANALYSIS)
    run_as_user(["bash", PROFILE])
    assert os.path.isfile(ANALYSIS), "profile.sh did not generate /home/user/analysis.json"
    after = open(METRICS, "rb").read()
    assert after == before, "profile.sh must analyze metrics.csv without replacing or modifying it"
    check_analysis(expected_values(df))


def test_metrics_csv_exists():
    assert os.path.isfile(METRICS), "The /home/user/metrics.csv file is missing. Did you run the load test?"


def test_analysis_json_exists():
    assert os.path.isfile(ANALYSIS), "The /home/user/analysis.json file is missing."


def test_profile_script_exists():
    assert os.path.isfile(PROFILE), "The required /home/user/profile.sh script is missing."
    assert os.path.getsize(PROFILE) > 0, "/home/user/profile.sh is empty."


def test_config_stack_load_and_profile():
    assert_configured()

    start_output = run_as_user(["bash", "/app/start_stack.sh"])
    assert "Stack started successfully." in start_output, "start_stack.sh did not successfully start the stack"

    if os.path.lexists(METRICS):
        os.remove(METRICS)
    load_output = run_as_user(["bash", "/app/run_load.sh"])
    assert "Load test complete." in load_output, "run_load.sh did not complete the load test"
    assert os.path.isfile(METRICS), "run_load.sh did not generate metrics.csv"

    canonical_df = read_metrics()
    assert canonical_df.shape == CANONICAL_ROWS.shape, "run_load.sh generated an unexpected number of rows"
    assert np.allclose(canonical_df.to_numpy(dtype=float), CANONICAL_ROWS, rtol=0, atol=1e-12), (
        "metrics.csv does not contain the load-test measurements produced by the configured stack"
    )
    canonical_bytes = open(METRICS, "rb").read()

    # Execute the submitted analyzer on the real load-test output.
    execute_profile_and_check(canonical_df)

    # Exercise the analyzer on an unpredictable valid data set so fixed answers cannot pass.
    rng = random.SystemRandom()
    times = [0.0]
    for _ in range(8):
        times.append(times[-1] + rng.uniform(0.35, 1.8))
    requests = [rng.uniform(8.0, 95.0) for _ in times]
    qa = rng.uniform(0.015, 0.075)
    qb = rng.uniform(-1.5, 2.5)
    qc = rng.uniform(5.0, 30.0)
    latencies = [qa * r * r + qb * r + qc + rng.uniform(-3.0, 3.0) for r in requests]
    cpus = [rng.uniform(10.0, 140.0) for _ in times]

    with open(METRICS, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(COLUMNS)
        writer.writerows(zip(times, requests, latencies, cpus))
    os.chown(METRICS, 1000, 1000)
    randomized_df = read_metrics()
    execute_profile_and_check(randomized_df)

    # Restore the genuine load-test state and regenerate its final analysis.json.
    with open(METRICS, "wb") as f:
        f.write(canonical_bytes)
    os.chown(METRICS, 1000, 1000)
    restored_df = read_metrics()
    execute_profile_and_check(restored_df)
    assert_configured()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
