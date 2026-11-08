#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import shutil
import subprocess

import pytest

SCRIPT_PATH = "/home/user/etl_pipeline.sh"
VENV_PATH = "/home/user/venv"
METRICS_PATH = "/home/user/metrics.json"
RAW_LOGS_PATH = "/home/user/raw_logs.txt"


def assert_two_decimal_json(path):
    text = open(path, "r", encoding="utf-8").read()
    parsed = json.loads(
        text,
        parse_float=lambda token: ("float", token),
        parse_int=lambda token: ("int", token),
    )
    assert set(parsed.keys()) == {"mean", "ci_lower", "ci_upper"}
    for key in ("mean", "ci_lower", "ci_upper"):
        value = parsed[key]
        assert isinstance(value, tuple) and value[0] == "float", \
            f"{key} must be written as a JSON floating-point number."
        assert re.fullmatch(r"-?\d+\.\d{2}", value[1]), \
            f"{key} must be written with exactly two decimal places, got {value[1]!r}."


def test_etl_pipeline_script_exists_and_executable():
    """Test that the ETL pipeline script exists and is executable."""
    script_path = "/home/user/etl_pipeline.sh"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_virtual_environment_exists():
    """Test that the virtual environment was created."""
    venv_path = "/home/user/venv"
    assert os.path.exists(venv_path), f"The virtual environment directory {venv_path} does not exist."
    assert os.path.isdir(venv_path), f"The path {venv_path} is not a directory."
    python_bin = os.path.join(venv_path, "bin", "python")
    assert os.path.exists(python_bin), f"Python interpreter not found in virtual environment at {python_bin}."


def test_metrics_json_exists_and_correct():
    """Test that metrics.json exists, is valid JSON, and contains the correct metrics."""
    metrics_path = "/home/user/metrics.json"
    assert os.path.exists(metrics_path), f"The file {metrics_path} does not exist."
    assert os.path.isfile(metrics_path), f"The path {metrics_path} is not a file."

    with open(metrics_path, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {metrics_path} does not contain valid JSON.")

    expected_keys = {"mean", "ci_lower", "ci_upper"}
    assert set(metrics.keys()) == expected_keys, f"metrics.json keys {set(metrics.keys())} do not match expected {expected_keys}."

    assert isinstance(metrics["mean"], (int, float)), "mean must be a number."
    assert isinstance(metrics["ci_lower"], (int, float)), "ci_lower must be a number."
    assert isinstance(metrics["ci_upper"], (int, float)), "ci_upper must be a number."

    assert round(metrics["mean"], 2) == 49.48, f"Expected mean 49.48, got {metrics['mean']}."
    assert round(metrics["ci_lower"], 2) == 48.58, f"Expected ci_lower 48.58, got {metrics['ci_lower']}."
    assert round(metrics["ci_upper"], 2) == 50.38, f"Expected ci_upper 50.38, got {metrics['ci_upper']}."
    assert_two_decimal_json(metrics_path)


def test_pipeline_executes_on_fresh_randomized_input_and_builds_real_venv():
    original_logs = open(RAW_LOGS_PATH, "rb").read()
    original_metrics = open(METRICS_PATH, "rb").read() if os.path.isfile(METRICS_PATH) else None

    rng = random.SystemRandom()
    base = rng.randint(25, 80)
    values = [
        base - 9 + rng.randint(1, 89) / 100,
        base - 4 + rng.randint(1, 89) / 100,
        base + 1 + rng.randint(1, 89) / 100,
        base + 7 + rng.randint(1, 89) / 100,
        base + 13 + rng.randint(1, 89) / 100,
    ]

    lines = []
    for i, value in enumerate(values):
        lines.append(
            f"[2026-01-02 03:04:{i:02d}] GET /api/v1/test | status: 200 | latency_ms: {value:.4f}\n"
        )
    lines[1:1] = [
        "[2026-01-02 03:05:01] GET /api/v1/test | status: 500 | latency_ms: NaN\n",
        "[2026-01-02 03:05:02] GET /api/v1/test | status: 404 | latency_ms: null\n",
    ]
    lines.extend([
        "[2026-01-02 03:05:03] GET /api/v1/test | status: 200 | latency_ms: \n",
        "[2026-01-02 03:05:04] GET /api/v1/test | status: 200 | latency_ms: corrupted\n",
        "[2026-01-02 03:05:05] GET /api/v1/test | status: 200 | latency_ms: 12oops\n",
    ])

    mean = sum(values) / len(values)
    sample_variance = sum((x - mean) ** 2 for x in values) / (len(values) - 1)
    sem = math.sqrt(sample_variance / len(values))
    # 97.5th percentile of Student's t with 4 degrees of freedom.
    margin = 2.7764451051977987 * sem
    expected = {
        "mean": float(f"{mean:.2f}"),
        "ci_lower": float(f"{mean - margin:.2f}"),
        "ci_upper": float(f"{mean + margin:.2f}"),
    }

    try:
        with open(RAW_LOGS_PATH, "w", encoding="utf-8") as f:
            f.writelines(lines)
        if os.path.lexists(METRICS_PATH):
            os.remove(METRICS_PATH)

        # Require the submitted script itself to create and populate the venv.
        if os.path.lexists(VENV_PATH):
            if os.path.islink(VENV_PATH):
                os.unlink(VENV_PATH)
            else:
                shutil.rmtree(VENV_PATH)

        result = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=360,
        )
        assert result.returncode == 0, f"Pipeline execution failed:\n{result.stdout}"
        assert os.path.isfile(METRICS_PATH), "Pipeline did not generate metrics.json."

        with open(METRICS_PATH, "r", encoding="utf-8") as f:
            metrics = json.load(f)
        assert set(metrics.keys()) == {"mean", "ci_lower", "ci_upper"}
        for key in expected:
            assert isinstance(metrics[key], (int, float)) and not isinstance(metrics[key], bool)
            assert metrics[key] == expected[key], \
                f"For randomized logs, expected {key}={expected[key]}, got {metrics[key]}."
        assert_two_decimal_json(METRICS_PATH)

        python_bin = os.path.join(VENV_PATH, "bin", "python")
        assert os.path.isfile(os.path.join(VENV_PATH, "pyvenv.cfg")), "venv is missing pyvenv.cfg."
        assert os.path.exists(python_bin) and os.access(python_bin, os.X_OK), \
            "venv Python is missing or not executable."

        probe_code = r'''
import json, os, sys
import numpy, scipy
print(json.dumps({
    "prefix": os.path.realpath(sys.prefix),
    "base_prefix": os.path.realpath(sys.base_prefix),
    "numpy": os.path.realpath(numpy.__file__),
    "scipy": os.path.realpath(scipy.__file__),
}))
'''
        probe = subprocess.run(
            [python_bin, "-c", probe_code],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert probe.returncode == 0, \
            f"NumPy and SciPy are not importable in the virtual environment: {probe.stderr}"
        info = json.loads(probe.stdout.strip().splitlines()[-1])
        real_venv = os.path.realpath(VENV_PATH)
        assert info["prefix"] == real_venv and info["base_prefix"] != real_venv, \
            "The submitted venv Python is not running as a real virtual environment."
        assert os.path.commonpath([real_venv, info["numpy"]]) == real_venv, \
            "NumPy is not installed inside the virtual environment."
        assert os.path.commonpath([real_venv, info["scipy"]]) == real_venv, \
            "SciPy is not installed inside the virtual environment."
    finally:
        with open(RAW_LOGS_PATH, "wb") as f:
            f.write(original_logs)
        if original_metrics is not None:
            with open(METRICS_PATH, "wb") as f:
                f.write(original_metrics)
        elif os.path.lexists(METRICS_PATH):
            os.remove(METRICS_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
