#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

import pytest

PROJECT_DIR = "/home/user/incident-1042"
SOURCE_PATH = os.path.join(PROJECT_DIR, "src/main.rs")
DATA_PATH = os.path.join(PROJECT_DIR, "data.csv")
RESOLUTION_PATH = "/home/user/resolution.txt"


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def parse_data(text):
    values = []
    for item in text.split(','):
        try:
            values.append(float(item.strip()))
        except ValueError:
            pass
    return values


def derivative(values):
    n = len(values)
    if n == 0:
        return []
    if n == 1:
        return [0.0]
    result = [0.0] * n
    result[0] = values[1] - values[0]
    for i in range(1, n - 1):
        result[i] = (values[i + 1] - values[i - 1]) / 2.0
    result[-1] = values[-1] - values[-2]
    return result


def parse_single_float(stdout):
    fields = stdout.split()
    assert len(fields) == 1, f"Application must print one floating-point number, got: {stdout!r}"
    try:
        value = float(fields[0])
    except ValueError as exc:
        raise AssertionError(f"Application output is not a floating-point number: {stdout!r}") from exc
    assert math.isfinite(value), f"Application returned a non-finite value: {value}"
    return value


def test_resolution_file_content():
    path = RESOLUTION_PATH
    assert os.path.isfile(path), f"Resolution file missing at {path}."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content in ["9900", "9900.0"], f"Incorrect resolution value in {path}. Expected 9900 or 9900.0, got '{content}'."


def test_test_boundary_conditions_exists():
    path = SOURCE_PATH
    assert os.path.isfile(path), f"Source file missing at {path}."

    with open(path, "r") as f:
        content = f.read()

    assert "fn test_boundary_conditions" in content, "The test function 'test_boundary_conditions' is missing in main.rs."

    listed = run(["cargo", "test", "--quiet", "--", "--list"], cwd=PROJECT_DIR)
    assert listed.returncode == 0, f"Could not list Rust tests:\n{listed.stdout}\n{listed.stderr}"
    tests = listed.stdout.splitlines()
    assert any(re.search(r"(^|::)test_boundary_conditions: test$", line.strip()) for line in tests), \
        "Cargo did not discover a test function named exactly 'test_boundary_conditions'."


def test_cargo_test_passes():
    assert os.path.isdir(PROJECT_DIR), f"Project directory {PROJECT_DIR} does not exist."

    result = run(["cargo", "test", "--quiet"], cwd=PROJECT_DIR)
    assert result.returncode == 0, f"`cargo test` failed with output:\n{result.stdout}\n{result.stderr}"


def test_compute_derivative_on_verifier_generated_inputs():
    assert os.path.isfile(SOURCE_PATH), f"Source file missing at {SOURCE_PATH}."
    rng = secrets.SystemRandom()
    cases = [
        [],
        [float(rng.randint(-1000, 1000))],
        [float(rng.randint(-1000, 1000)) for _ in range(2)],
        [float(rng.randint(-1000, 1000)) for _ in range(7)],
        [float(rng.randint(-1000, 1000)) for _ in range(13)],
    ]
    module_name = "verifier_" + secrets.token_hex(8)

    rust_cases = []
    for values in cases:
        expected = derivative(values)
        input_values = ", ".join(repr(v) for v in values)
        expected_values = ", ".join(repr(v) for v in expected)
        rust_cases.append(f'''\n            {{\n                let input: Vec<f64> = vec![{input_values}];\n                let expected: Vec<f64> = vec![{expected_values}];\n                let actual = super::compute_derivative(&input);\n                assert_eq!(actual.len(), expected.len());\n                for (got, want) in actual.iter().zip(expected.iter()) {{\n                    assert!((got - want).abs() < 1e-10, "got {{:?}}, expected {{:?}}", actual, expected);\n                }}\n            }}''')

    injected = f'''\n\n#[cfg(test)]\nmod {module_name} {{\n    #[test]\n    fn generated_derivative_cases() {{\n        {''.join(rust_cases)}\n    }}\n}}\n'''

    with open(SOURCE_PATH, "r") as f:
        original = f.read()
    try:
        with open(SOURCE_PATH, "w") as f:
            f.write(original)
            f.write(injected)
        result = run(["cargo", "test", "--quiet", module_name], cwd=PROJECT_DIR)
        assert result.returncode == 0, \
            f"compute_derivative failed verifier-generated boundary/interior cases:\n{result.stdout}\n{result.stderr}"
    finally:
        with open(SOURCE_PATH, "w") as f:
            f.write(original)


def test_corrected_application_and_resolution_are_derived_from_data():
    assert os.path.isfile(DATA_PATH), f"Production data missing at {DATA_PATH}."
    with open(DATA_PATH, "r") as f:
        production_text = f.read()

    production_values = parse_data(production_text)
    production_expected = sum(derivative(production_values))
    assert math.isclose(production_expected, 9900.0, rel_tol=0.0, abs_tol=1e-9), \
        "Production data.csv was unexpectedly modified."

    production_run = run(["cargo", "run", "--quiet"], cwd=PROJECT_DIR)
    assert production_run.returncode == 0, \
        f"Corrected application failed on production data:\n{production_run.stdout}\n{production_run.stderr}"
    production_actual = parse_single_float(production_run.stdout)
    assert math.isclose(production_actual, production_expected, rel_tol=1e-10, abs_tol=1e-9), \
        f"Application produced {production_actual}, expected {production_expected} from data.csv."

    with open(RESOLUTION_PATH, "r") as f:
        resolution = parse_single_float(f.read())
    assert math.isclose(resolution, production_expected, rel_tol=1e-10, abs_tol=1e-9), \
        f"resolution.txt contains {resolution}, expected the computed result {production_expected}."

    rng = secrets.SystemRandom()
    runtime_cases = [
        [],
        [float(rng.randint(-5000, 5000))],
        [float(rng.randint(-5000, 5000)) for _ in range(2)],
        [float(rng.randint(-5000, 5000)) for _ in range(9)],
    ]
    try:
        for values in runtime_cases:
            with open(DATA_PATH, "w") as f:
                f.write(",".join(repr(v) for v in values))
            expected = sum(derivative(values))
            result = run(["cargo", "run", "--quiet"], cwd=PROJECT_DIR)
            assert result.returncode == 0, \
                f"Application failed on verifier-generated input {values}:\n{result.stdout}\n{result.stderr}"
            actual = parse_single_float(result.stdout)
            assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-9), \
                f"Application returned {actual} for {values}, expected {expected}."
    finally:
        with open(DATA_PATH, "w") as f:
            f.write(production_text)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
