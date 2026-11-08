#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import struct
import subprocess
import pytest

SOURCE_PATH = "/home/user/artifact_analyzer.c"
WEIGHTS_PATH = "/home/user/weights.bin"
OUTPUT_PATH = "/home/user/artifact_metrics.json"
EXECUTABLE_PATH = "/tmp/verifier_artifact_analyzer"

assert os.path.isfile(WEIGHTS_PATH), f"Missing file: {WEIGHTS_PATH}"
with open(WEIGHTS_PATH, "rb") as f:
    ORIGINAL_WEIGHTS = f.read()


def expected_metrics(values):
    n = len(values)
    mean = sum(values) / n
    variance = sum((x - mean) ** 2 for x in values) / n
    stddev = math.sqrt(variance)
    margin = 1.96 * (stddev / math.sqrt(n))
    return mean, mean - margin, mean + margin


def read_metrics():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist. Did you run the compiled C program?"
    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")

    assert "mean" in data, "Missing 'mean' key in JSON output."
    assert "ci_lower" in data, "Missing 'ci_lower' key in JSON output."
    assert "ci_upper" in data, "Missing 'ci_upper' key in JSON output."
    return data


def run_analyzer(values):
    with open(WEIGHTS_PATH, "wb") as f:
        f.write(struct.pack(f"={len(values)}d", *values))

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [EXECUTABLE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled analyzer exited with status {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    return read_metrics()


@pytest.fixture(scope="session", autouse=True)
def restore_original_artifact():
    yield
    with open(WEIGHTS_PATH, "wb") as f:
        f.write(ORIGINAL_WEIGHTS)
    if os.path.isfile(EXECUTABLE_PATH):
        try:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
            subprocess.run([EXECUTABLE_PATH], timeout=10, check=False)
        except Exception:
            pass


@pytest.fixture(scope="session")
def compiled_analyzer():
    assert os.path.isfile(SOURCE_PATH), f"Missing C source: {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, f"C source is empty: {SOURCE_PATH}"

    result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", EXECUTABLE_PATH, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Fixed C source did not compile:\n{result.stderr}"
    assert os.path.isfile(EXECUTABLE_PATH), "Compilation did not produce an executable."
    assert os.access(EXECUTABLE_PATH, os.X_OK), "Compiled artifact is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled artifact is not an ELF executable."
    return EXECUTABLE_PATH


def test_fixed_c_program_on_derived_input(compiled_analyzer):
    # Exercise the submitted C source on data not present during the agent run.
    values = [((i % 23) - 11) * 0.25 + (i % 5) * 0.01 for i in range(10000)]
    data = run_analyzer(values)
    expected_mean, expected_lower, expected_upper = expected_metrics(values)

    assert math.isclose(data["mean"], expected_mean, rel_tol=0, abs_tol=1e-5)
    assert math.isclose(data["ci_lower"], expected_lower, rel_tol=0, abs_tol=1e-5)
    assert math.isclose(data["ci_upper"], expected_upper, rel_tol=0, abs_tol=1e-5)


@pytest.fixture(scope="session")
def original_output(compiled_analyzer):
    assert len(ORIGINAL_WEIGHTS) == 10000 * 8, "Weights file size is incorrect."
    values = struct.unpack("=10000d", ORIGINAL_WEIGHTS)
    return run_analyzer(values)


def test_artifact_metrics_json_exists(original_output):
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist. Did you run the compiled C program?"


def test_artifact_metrics_values(original_output):
    output_path = OUTPUT_PATH
    assert os.path.isfile(output_path), "Output file missing."

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} is not valid JSON.")

    assert "mean" in data, "Missing 'mean' key in JSON output."
    assert "ci_lower" in data, "Missing 'ci_lower' key in JSON output."
    assert "ci_upper" in data, "Missing 'ci_upper' key in JSON output."

    # Compute expected values from the binary file directly to be robust
    weights_path = WEIGHTS_PATH
    assert os.path.isfile(weights_path), f"Missing file: {weights_path}"

    with open(weights_path, 'rb') as f:
        binary_data = f.read()

    # 10000 doubles
    n = 10000
    assert len(binary_data) == n * 8, "Weights file size is incorrect."
    assert binary_data == ORIGINAL_WEIGHTS, "The analyzer modified the input weights file."

    values = struct.unpack(f"{n}d", binary_data)

    expected_mean = sum(values) / n
    expected_variance = sum((x - expected_mean) ** 2 for x in values) / n
    expected_stddev = math.sqrt(expected_variance)
    expected_margin = 1.96 * (expected_stddev / math.sqrt(n))

    expected_ci_lower = expected_mean - expected_margin
    expected_ci_upper = expected_mean + expected_margin

    # The C code formats to 6 decimal places, so we check within 1e-5
    assert math.isclose(data["mean"], expected_mean, abs_tol=1e-5), \
        f"Expected mean ~{expected_mean:.6f}, got {data['mean']}"

    assert math.isclose(data["ci_lower"], expected_ci_lower, abs_tol=1e-5), \
        f"Expected ci_lower ~{expected_ci_lower:.6f}, got {data['ci_lower']}"

    assert math.isclose(data["ci_upper"], expected_ci_upper, abs_tol=1e-5), \
        f"Expected ci_upper ~{expected_ci_upper:.6f}, got {data['ci_upper']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
