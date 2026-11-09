#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/root/.cargo/bin:/home/user/.cargo/bin:${PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import statistics
import subprocess

import pytest

PROJECT_DIR = "/home/user/temp_analyzer"
CARGO_TOML = os.path.join(PROJECT_DIR, "Cargo.toml")
SOURCE_FILE = os.path.join(PROJECT_DIR, "src", "main.rs")
SUMMARY_FILE = "/home/user/summary.json"
SENSOR_FILE = "/home/user/sensor_logs.txt"


def load_summary():
    with open(SUMMARY_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {SUMMARY_FILE} does not contain valid JSON.")


def assert_summary(expected, tolerance=0.011):
    data = load_summary()
    expected_keys = {"mean", "std_dev", "ci_lower", "ci_upper"}
    assert set(data.keys()) == expected_keys, (
        f"JSON keys {list(data.keys())} do not match expected {list(expected_keys)}."
    )

    for key, value in expected.items():
        actual = data[key]
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), (
            f"{key} must be a JSON number, got {actual!r}"
        )
        assert math.isfinite(actual), f"{key} must be finite, got {actual}"
        assert abs(actual - value) <= tolerance, (
            f"Expected {key} ~{value:.2f}, got {actual}"
        )


def run_program():
    subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", CARGO_TOML],
        cwd=PROJECT_DIR,
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_rust_project_exists():
    project_dir = "/home/user/temp_analyzer"
    cargo_toml = os.path.join(project_dir, "Cargo.toml")

    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} does not exist."
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found at {cargo_toml}."


def test_summary_json_exists():
    summary_file = "/home/user/summary.json"
    assert os.path.isfile(summary_file), f"Summary JSON file {summary_file} does not exist."


def test_summary_json_content():
    summary_file = "/home/user/summary.json"

    with open(summary_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {summary_file} does not contain valid JSON.")

    expected_keys = {"mean", "std_dev", "ci_lower", "ci_upper"}
    assert set(data.keys()) == expected_keys, f"JSON keys {list(data.keys())} do not match expected {list(expected_keys)}."

    # Assert values with a small tolerance for rounding differences
    assert abs(data["mean"] - 46.05) <= 0.01, f"Expected mean ~46.05, got {data['mean']}"
    assert abs(data["std_dev"] - 1.37) <= 0.01, f"Expected std_dev ~1.37, got {data['std_dev']}"
    assert abs(data["ci_lower"] - 45.07) <= 0.01, f"Expected ci_lower ~45.07, got {data['ci_lower']}"
    assert abs(data["ci_upper"] - 47.03) <= 0.01, f"Expected ci_upper ~47.03, got {data['ci_upper']}"


def test_rust_source_builds_and_generates_original_summary():
    assert os.path.isfile(SOURCE_FILE), f"Rust source file not found at {SOURCE_FILE}."
    assert os.path.getsize(SOURCE_FILE) > 0, f"Rust source file {SOURCE_FILE} is empty."

    subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", CARGO_TOML],
        cwd=PROJECT_DIR,
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    if os.path.exists(SUMMARY_FILE):
        os.remove(SUMMARY_FILE)
    run_program()
    assert os.path.isfile(SUMMARY_FILE), "Running the Rust program did not create summary.json."
    assert_summary({
        "mean": 46.05,
        "std_dev": 1.37,
        "ci_lower": 45.07,
        "ci_upper": 47.03,
    })


def test_program_parses_changed_sensor_data():
    with open(SENSOR_FILE, "rb") as f:
        original_sensor = f.read()
    original_summary = None
    if os.path.exists(SUMMARY_FILE):
        with open(SUMMARY_FILE, "rb") as f:
            original_summary = f.read()

    rng = secrets.SystemRandom()
    # For n=6, the two-sided 95% Student-t critical value has 5 degrees of freedom.
    t_critical = 2.570581835636305

    try:
        for _ in range(2):
            offset = rng.uniform(-35.0, 70.0)
            scale = rng.uniform(0.65, 2.10)
            base = [-3.17, -1.02, 0.44, 2.31, 4.86, 7.22]
            values = [float(f"{offset + scale * x:.6f}") for x in base]

            lines = [
                f"record-X temperature {value:.6f} C\n"
                for value in values
            ]
            lines.extend([
                "corrupt Sensor-1 N/A err temp=999.9\n",
                "no-reading token42 88.8C value:-123.4\n",
            ])
            rng.shuffle(lines)
            with open(SENSOR_FILE, "w") as f:
                f.writelines(lines)

            if os.path.exists(SUMMARY_FILE):
                os.remove(SUMMARY_FILE)
            run_program()
            assert os.path.isfile(SUMMARY_FILE), (
                "Running the Rust program on changed input did not create summary.json."
            )

            mean = statistics.mean(values)
            std_dev = statistics.stdev(values)
            margin = t_critical * std_dev / math.sqrt(len(values))
            assert_summary({
                "mean": round(mean, 2),
                "std_dev": round(std_dev, 2),
                "ci_lower": round(mean - margin, 2),
                "ci_upper": round(mean + margin, 2),
            })
    finally:
        with open(SENSOR_FILE, "wb") as f:
            f.write(original_sensor)
        if original_summary is None:
            if os.path.exists(SUMMARY_FILE):
                os.remove(SUMMARY_FILE)
        else:
            with open(SUMMARY_FILE, "wb") as f:
                f.write(original_summary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
