#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import statistics
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/anomaly_detector"
SOURCE = os.path.join(PROJECT, "src/main.rs")
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
CSV_FILE = "/home/user/sensor_data.csv"
OUTPUT_FILE = "/home/user/fixed_output.txt"


def parse_floats(text, source_name):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    values = []
    for i, line in enumerate(lines):
        try:
            value = float(line)
        except ValueError:
            pytest.fail(f"Line {i+1} in {source_name} is not a valid float: '{line}'")
        assert math.isfinite(value), f"Line {i+1} in {source_name} is not finite: '{line}'"
        assert value >= 0.0, f"Line {i+1} in {source_name} is negative: {value}"
        values.append(value)
    return values


def expected_from_csv(path):
    expected = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            values = [float(x) for x in line.split(",")]
            expected.append(statistics.pvariance(values))
    return expected


def assert_variances(actual, expected, source_name):
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} lines of output from {source_name}, but found {len(actual)}."
    )
    for i, (actual_val, expected_val) in enumerate(zip(actual, expected)):
        assert math.isclose(actual_val, expected_val, rel_tol=1e-5, abs_tol=1e-8), (
            f"Variance mismatch on line {i+1}: expected {expected_val}, got {actual_val}. "
            "Make sure you are calculating the population variance using a numerically stable algorithm."
        )


@pytest.fixture(scope="session")
def compiled_program():
    assert os.path.isfile(SOURCE), f"Rust source file {SOURCE} is missing."
    assert os.path.isfile(MANIFEST), f"Cargo manifest {MANIFEST} is missing."

    clean = subprocess.run(
        ["cargo", "clean", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}\n{clean.stderr}"

    build = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", MANIFEST, "--message-format=json"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert build.returncode == 0, f"Rust project did not compile:\n{build.stdout}\n{build.stderr}"

    executable = None
    canonical_source = os.path.realpath(SOURCE)
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = message.get("target", {})
        if (
            message.get("reason") == "compiler-artifact"
            and "bin" in target.get("kind", [])
            and os.path.realpath(target.get("src_path", "")) == canonical_source
            and message.get("executable")
        ):
            executable = message["executable"]

    assert executable, "Cargo did not build an executable from src/main.rs."
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), (
        f"Built artifact {executable} is not an executable file."
    )
    return executable


def run_program(executable, input_path):
    result = subprocess.run(
        [executable, input_path],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"The compiled program failed on {input_path} with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return parse_floats(result.stdout, "compiled program stdout")


def test_fixed_output_exists():
    """Check if the fixed_output.txt file was created."""
    assert os.path.isfile(OUTPUT_FILE), (
        f"Output file {OUTPUT_FILE} does not exist. Did you redirect the output?"
    )


def test_fixed_output_values():
    """Verify that the output file contains the correct population variances."""
    assert os.path.isfile(CSV_FILE), f"Input file {CSV_FILE} is missing."
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."

    expected_variances = expected_from_csv(CSV_FILE)
    with open(OUTPUT_FILE, "r") as f:
        actual_values = parse_floats(f.read(), OUTPUT_FILE)
    assert_variances(actual_values, expected_variances, OUTPUT_FILE)


def test_compiled_program_produced_production_results(compiled_program):
    expected = expected_from_csv(CSV_FILE)
    program_values = run_program(compiled_program, CSV_FILE)
    assert_variances(program_values, expected, "production data")

    with open(OUTPUT_FILE, "r") as f:
        redirected_values = parse_floats(f.read(), OUTPUT_FILE)
    assert len(program_values) == len(redirected_values)
    for i, (program_value, file_value) in enumerate(zip(program_values, redirected_values)):
        assert math.isclose(program_value, file_value, rel_tol=1e-12, abs_tol=1e-12), (
            f"fixed_output.txt line {i+1} does not match the compiled program's production output."
        )


def test_compiled_program_on_unseen_precision_inputs(compiled_program):
    rng = secrets.SystemRandom()
    rows = []

    for _ in range(3):
        base = rng.randrange(80_000_000, 180_000_000)
        units = [rng.randrange(-32, 33) for _ in range(rng.randrange(9, 18))]
        while len(set(units)) < 4:
            units = [rng.randrange(-32, 33) for _ in range(rng.randrange(9, 18))]
        rows.append([base + unit * 0.125 for unit in units])

    rows.append([float(rng.randrange(-1000, 1001)) for _ in range(13)])
    constant = float(rng.randrange(1_000_000, 2_000_000))
    rows.append([constant] * 7)
    rows.append([float(rng.randrange(-1000, 1001))])

    csv_lines = [",".join(format(value, ".17g") for value in row) for row in rows]
    csv_text = "\n".join(csv_lines) + "\n"

    with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
        f.write(csv_text)
        test_path = f.name

    try:
        expected = expected_from_csv(test_path)
        actual = run_program(compiled_program, test_path)
        assert_variances(actual, expected, "unseen precision-stress data")
    finally:
        os.unlink(test_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
