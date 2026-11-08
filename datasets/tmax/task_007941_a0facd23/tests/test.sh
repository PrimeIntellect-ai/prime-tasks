#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import pytest

VENV_PYTHON = "/home/user/bio_env/bin/python"
SMOOTH_BIN = "/home/user/bin/smooth"
RAW_PATH = "/home/user/raw_data.txt"
SMOOTHED_PATH = "/home/user/smoothed.txt"
LOG_PATH = "/home/user/svd_results.log"


def run_smoother(input_bytes):
    try:
        result = subprocess.run(
            [SMOOTH_BIN],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            timeout=10,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Smoother did not execute successfully: {exc}")
    return result.stdout


def expected_smoothing(values):
    output = []
    for i, value in enumerate(values):
        prev = value if i == 0 else values[i - 1]
        next_value = value if i == len(values) - 1 else values[i + 1]
        output.append(f"{(prev + value + next_value) / 3.0:.6f}\n")
    return "".join(output).encode("ascii")


def test_venv_exists():
    assert os.path.isfile(VENV_PYTHON), f"Virtual environment python not found at {VENV_PYTHON}"


def test_numpy_installed():
    try:
        subprocess.run(
            [VENV_PYTHON, "-c", "import numpy"],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"numpy is not installed in the virtual environment. Error: {e.stderr}")


def test_smooth_executable_exists():
    assert os.path.isfile(SMOOTH_BIN), f"Compiled executable not found at {SMOOTH_BIN}"
    assert os.access(SMOOTH_BIN, os.X_OK), f"File at {SMOOTH_BIN} is not executable"
    with open(SMOOTH_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SMOOTH_BIN} is not a compiled ELF executable"


def test_smoothed_data_exists():
    assert os.path.isfile(SMOOTHED_PATH), f"Smoothed data file not found at {SMOOTHED_PATH}"
    with open(SMOOTHED_PATH, "r") as f:
        lines = f.read().strip().splitlines()
    assert len(lines) == 5000, f"Expected 5000 lines in {SMOOTHED_PATH}, found {len(lines)}"


def test_compiled_smoother_and_saved_pipeline_output():
    with open(RAW_PATH, "rb") as f:
        raw_bytes = f.read()
    raw_values = [float(line) for line in raw_bytes.decode("ascii").splitlines()]
    assert len(raw_values) == 5000, f"Expected 5000 raw values, found {len(raw_values)}"

    actual_run = run_smoother(raw_bytes)
    expected_run = expected_smoothing(raw_values)
    assert actual_run == expected_run, "Compiled smoother output does not implement the supplied moving-average algorithm"

    with open(SMOOTHED_PATH, "rb") as f:
        saved_output = f.read()
    assert saved_output == actual_run, "smoothed.txt is not the output produced by running smooth on raw_data.txt"


def test_smoother_on_independent_inputs():
    probes = [
        [4.25],
        [-3.5, 2.25, 11.75, -8.125, 0.5],
    ]
    rng = random.SystemRandom()
    probes.append([float(f"{rng.uniform(-1000, 1000):.9f}") for _ in range(37)])

    for values in probes:
        input_bytes = "".join(f"{value:.9f}\n" for value in values).encode("ascii")
        parsed_values = [float(line) for line in input_bytes.decode("ascii").splitlines()]
        assert run_smoother(input_bytes) == expected_smoothing(parsed_values)


def test_svd_results_correct():
    assert os.path.isfile(LOG_PATH), f"SVD results log not found at {LOG_PATH}"

    expected_values = [
        "3507.0305",
        "55.4855",
        "52.5028",
        "50.3957",
        "47.3695",
    ]

    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines() if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 lines in {LOG_PATH}, found {len(lines)}"
    for i, (actual, expected) in enumerate(zip(lines, expected_values)):
        assert actual == expected, f"Mismatch at line {i+1}: expected {expected}, got {actual}"
        assert re.fullmatch(r"-?\d+\.\d{4}", actual), f"Line {i+1} is not formatted to exactly 4 decimal places"

    calculation = subprocess.run(
        [
            VENV_PYTHON,
            "-c",
            "import numpy as np; a=np.loadtxt('/home/user/smoothed.txt').reshape((100,50), order='C'); print('\\n'.join(f'{x:.4f}' for x in np.linalg.svd(a, compute_uv=False)[:5]))",
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=30,
    )
    derived_values = calculation.stdout.strip().splitlines()
    assert lines == derived_values, "svd_results.log was not derived from the saved 100x50 smoothed-data matrix"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
