#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess

import pytest

PROJECT = "/home/user/data_pipeline"
MAIN_RS = os.path.join(PROJECT, "src/main.rs")
SENSOR_DATA = "/home/user/sensor_data.txt"


def test_main_rs_recovered():
    """Verify that the deleted main.rs file has been recovered."""
    assert os.path.isfile(MAIN_RS), (
        "The file /home/user/data_pipeline/src/main.rs has not been recovered."
    )


def test_cargo_builds():
    """Verify that the Rust project compiles successfully (compiler error fixed)."""
    assert os.path.isfile(MAIN_RS), "main.rs is missing."

    result = subprocess.run(
        ["cargo", "build"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Cargo build failed. The recovered code may still have compiler errors.\n"
        f"Stderr:\n{result.stderr}"
    )


def test_anomaly_txt_content():
    """Verify that the anomaly value was correctly identified and written to the report file."""
    anomaly_path = "/home/user/anomaly.txt"
    assert os.path.isfile(anomaly_path), f"The report file {anomaly_path} does not exist."

    with open(anomaly_path, "r") as f:
        content = f.read().strip()

    assert content == "5000.5", (
        f"The anomaly value in {anomaly_path} is incorrect. "
        f"Expected '5000.5', got '{content}'."
    )


def _expected_anomalies(values):
    n = float(len(values))
    mean = sum(values) / n
    variance = sum((mean - value) ** 2 for value in values) / n
    std_dev = math.sqrt(variance)
    return [value for value in values if abs(value - mean) > 3.0 * std_dev]


def _rust_display(value):
    if value.is_integer():
        return str(int(value))
    return str(value)


def _run_binary(binary):
    result = subprocess.run(
        [binary],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"The compiled pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def test_program_computes_anomaly_from_sensor_data():
    """Execute the submitted Rust binary on original and verifier-generated data."""
    assert os.path.isfile(MAIN_RS), "main.rs is missing."

    build = subprocess.run(
        ["cargo", "build"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, f"Cargo build failed:\n{build.stderr}"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    main_real = os.path.realpath(MAIN_RS)
    binary_targets = [
        target
        for package in metadata["packages"]
        for target in package["targets"]
        if "bin" in target["kind"] and os.path.realpath(target["src_path"]) == main_real
    ]
    assert binary_targets, "Cargo does not define src/main.rs as a binary target."

    binary = os.path.join(PROJECT, "target", "debug", binary_targets[0]["name"])
    assert os.path.isfile(binary), f"Expected compiled binary {binary} was not produced."
    assert os.access(binary, os.X_OK), f"Compiled artifact {binary} is not executable."

    original_output = _run_binary(binary)
    assert original_output == ["5000.5"], (
        "The compiled Rust program did not produce the expected anomaly for the "
        f"provided sensor data. Got: {original_output!r}"
    )

    with open(SENSOR_DATA, "rb") as f:
        original_sensor_data = f.read()

    rng = secrets.SystemRandom()
    generated_cases = []

    baseline = float(rng.randint(-100, 100)) + 0.25
    values = [baseline] * rng.randint(40, 80)
    values.insert(rng.randrange(len(values) + 1), baseline + rng.choice([-1, 1]) * 1000.5)
    generated_cases.append(values)

    center = rng.randint(-200, 200)
    values = [center + rng.randint(-20, 20) / 10.0 for _ in range(60)]
    values.append(center + rng.choice([-1, 1]) * 500.5)
    rng.shuffle(values)
    generated_cases.append(values)

    try:
        for values in generated_cases:
            expected_values = _expected_anomalies(values)
            assert len(expected_values) == 1, "Verifier generated an invalid test case."
            expected = [_rust_display(value) for value in expected_values]

            with open(SENSOR_DATA, "w") as f:
                for value in values:
                    f.write(f"{value}\n")

            actual = _run_binary(binary)
            assert actual == expected, (
                "The compiled Rust program did not compute the anomaly for a "
                f"verifier-generated sensor dataset. Expected {expected!r}, got {actual!r}."
            )
    finally:
        with open(SENSOR_DATA, "wb") as f:
            f.write(original_sensor_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
