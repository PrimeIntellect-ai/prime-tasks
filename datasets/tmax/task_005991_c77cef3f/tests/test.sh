#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import re
import secrets
import subprocess
import pytest

BIN_PATH = "/home/user/bin/welford_ref"
SOURCE_PATH = "/home/user/src/welford_ref.c"
GO_PATH = "/home/user/src/stats.go"
INPUT_PATH = "/home/user/data/input.csv"
REF_OUTPUT_PATH = "/home/user/output/ref_output.txt"
JSON_PATH = "/home/user/output/results.json"


def test_welford_ref_executable():
    """Check that the compiled C binary exists and is executable."""
    bin_path = BIN_PATH
    assert os.path.isfile(bin_path), f"Executable {bin_path} is missing."
    assert os.access(bin_path, os.X_OK), f"File {bin_path} is not executable."

    # Check that it's an ELF file
    with open(bin_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"File {bin_path} is not a valid ELF executable."


def test_ref_output_txt():
    """Check that ref_output.txt exists and contains the correct reference output."""
    output_path = REF_OUTPUT_PATH
    assert os.path.isfile(output_path), f"File {output_path} is missing."

    with open(output_path, "r") as f:
        content = f.read()

    assert "Mean: 1000000000.4999500000" in content, "ref_output.txt does not contain the correct Mean."
    assert "Sample Variance: 0.0833416667" in content, "ref_output.txt does not contain the correct Sample Variance."

    # The saved file must be the exact stdout produced by the submitted binary.
    completed = subprocess.run(
        [BIN_PATH, INPUT_PATH], capture_output=True, timeout=15, check=False
    )
    assert completed.returncode == 0, (
        f"welford_ref failed on input.csv: {completed.stderr.decode(errors='replace')}"
    )
    with open(output_path, "rb") as f:
        saved = f.read()
    assert completed.stdout == saved, "ref_output.txt is not the exact stdout of welford_ref."


def test_results_json():
    """Check that results.json exists, is valid JSON, and contains correct calculations."""
    json_path = JSON_PATH
    assert os.path.isfile(json_path), f"File {json_path} is missing."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    required_keys = {"naive_variance", "welford_variance", "welford_mean"}
    assert required_keys.issubset(data.keys()), f"results.json is missing one or more required keys: {required_keys - data.keys()}"

    welford_var = data["welford_variance"]
    welford_mean = data["welford_mean"]
    naive_var = data["naive_variance"]

    assert isinstance(welford_var, (int, float)), "welford_variance must be a number."
    assert isinstance(welford_mean, (int, float)), "welford_mean must be a number."
    assert isinstance(naive_var, (int, float)), "naive_variance must be a number."

    assert math.isclose(welford_mean, 1000000000.4999500000, abs_tol=1e-5), \
        f"welford_mean {welford_mean} is not close to the expected value 1000000000.4999500000."

    assert math.isclose(welford_var, 0.0833416667, abs_tol=1e-5), \
        f"welford_variance {welford_var} is not close to the expected value 0.0833416667."

    assert abs(naive_var - welford_var) >= 1.0, \
        f"naive_variance ({naive_var}) is too close to welford_variance ({welford_var}). It should demonstrate catastrophic cancellation."


def expected_statistics(values):
    total = 0.0
    sum_squares = 0.0
    count = 0.0
    mean = 0.0
    m2 = 0.0

    for x in values:
        total += x
        sum_squares += x * x
        count += 1.0
        delta = x - mean
        mean += delta / count
        m2 += delta * (x - mean)

    naive = (sum_squares - (total * total) / count) / (count - 1.0)
    variance = m2 / (count - 1.0)
    return naive, variance, mean


def write_input(values):
    with open(INPUT_PATH, "w") as f:
        for value in values:
            f.write(repr(float(value)) + "\n")


def read_generated_json():
    assert os.path.isfile(JSON_PATH), "stats.go did not create results.json."
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"stats.go created invalid JSON: {exc}")

    required = {"naive_variance", "welford_variance", "welford_mean"}
    assert required.issubset(data), f"Generated results.json is missing keys: {required - data.keys()}"
    for key in required:
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{key} must be numeric."
        assert math.isfinite(value), f"{key} must be finite."
    return data


def test_artifacts_execute_on_unpredictable_inputs():
    """Execute both submitted artifacts on verifier-generated datasets."""
    assert os.path.isfile(SOURCE_PATH), f"C source {SOURCE_PATH} is missing."
    assert os.path.isfile(GO_PATH), f"Go source {GO_PATH} is missing."

    rng = secrets.SystemRandom()
    ordinary = [rng.randint(-20000, 20000) / 32.0 for _ in range(137)]
    base = float(rng.randint(100000000, 10000000000))
    large_mean = [base + rng.randint(-5000, 5000) / 64.0 for _ in range(257)]
    asymmetric = [rng.randint(-100000, 100000) / 128.0 for _ in range(91)]
    asymmetric.extend([rng.randint(1000, 5000) / 7.0 for _ in range(47)])
    datasets = [ordinary, large_mean, asymmetric]

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()
    original_results = None
    if os.path.isfile(JSON_PATH):
        with open(JSON_PATH, "rb") as f:
            original_results = f.read()

    try:
        for values in datasets:
            write_input(values)
            expected_naive, expected_var, expected_mean = expected_statistics(values)

            # Exercise the submitted ELF and verify both its calculations and format.
            c_run = subprocess.run(
                [BIN_PATH, INPUT_PATH], capture_output=True, text=True,
                timeout=15, check=False
            )
            assert c_run.returncode == 0, f"welford_ref failed: {c_run.stderr}"
            expected_stdout = (
                f"Mean: {expected_mean:.10f}\n"
                f"Sample Variance: {expected_var:.10f}\n"
            )
            assert c_run.stdout == expected_stdout, (
                "welford_ref produced incorrect output for a verifier-generated dataset."
            )

            # Remove stale output, then execute the requested Go source itself.
            if os.path.exists(JSON_PATH):
                os.remove(JSON_PATH)
            go_run = subprocess.run(
                ["go", "run", GO_PATH], cwd="/home/user/src",
                capture_output=True, text=True, timeout=60, check=False
            )
            assert go_run.returncode == 0, f"go run stats.go failed: {go_run.stderr}"
            data = read_generated_json()

            mean_tol = max(1e-10, abs(expected_mean) * 2e-15)
            assert math.isclose(data["welford_mean"], expected_mean, rel_tol=0.0, abs_tol=mean_tol), (
                f"Incorrect Welford mean: got {data['welford_mean']}, expected {expected_mean}"
            )
            assert math.isclose(data["welford_variance"], expected_var, rel_tol=1e-9, abs_tol=1e-9), (
                f"Incorrect Welford variance: got {data['welford_variance']}, expected {expected_var}"
            )
            assert math.isclose(data["naive_variance"], expected_naive, rel_tol=1e-12, abs_tol=1e-9), (
                f"Incorrect naive variance: got {data['naive_variance']}, expected {expected_naive}"
            )
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        if original_results is None:
            if os.path.exists(JSON_PATH):
                os.remove(JSON_PATH)
        else:
            with open(JSON_PATH, "wb") as f:
                f.write(original_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
