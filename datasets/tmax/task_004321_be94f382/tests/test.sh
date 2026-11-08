#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pathlib
import random
import re
import subprocess

import pytest

DATA_PATH = pathlib.Path("/home/user/data/experiment_metrics.csv")
RESULT_PATH = pathlib.Path("/home/user/regression_result.json")
PROJECT_PATH = pathlib.Path("/home/user/schema_enforcer")


@pytest.fixture(scope="session", autouse=True)
def restore_agent_files():
    original_data = DATA_PATH.read_bytes()
    original_result = RESULT_PATH.read_bytes() if RESULT_PATH.is_file() else None
    yield
    DATA_PATH.write_bytes(original_data)
    if original_result is None:
        RESULT_PATH.unlink(missing_ok=True)
    else:
        RESULT_PATH.write_bytes(original_result)


def test_regression_result_exists():
    """Test that the regression_result.json file was created."""
    file_path = "/home/user/regression_result.json"
    assert os.path.isfile(file_path), f"Expected file {file_path} was not found."


def test_regression_result_content():
    """Test that the regression_result.json file contains the correct model parameters."""
    file_path = "/home/user/regression_result.json"
    assert os.path.isfile(file_path), f"Expected file {file_path} was not found."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert "slope" in data, "JSON is missing the 'slope' key."
    assert "intercept" in data, "JSON is missing the 'intercept' key."

    # Check values with a small tolerance for floating point representation of 4 decimal places
    expected_slope = 1.8000
    expected_intercept = 3.3333

    slope = data["slope"]
    intercept = data["intercept"]

    assert isinstance(slope, (int, float)), f"'slope' must be a number, got {type(slope)}"
    assert isinstance(intercept, (int, float)), f"'intercept' must be a number, got {type(intercept)}"

    assert round(slope, 4) == expected_slope, f"Expected slope to be {expected_slope}, but got {slope}"
    assert round(intercept, 4) == expected_intercept, f"Expected intercept to be {expected_intercept}, but got {intercept}"


def test_rust_project_exists():
    assert PROJECT_PATH.is_dir(), "Expected /home/user/schema_enforcer to be a Rust project directory."
    assert (PROJECT_PATH / "Cargo.toml").is_file(), "Rust project is missing Cargo.toml."
    assert any(PROJECT_PATH.rglob("*.rs")), "Rust project contains no Rust source files."


def test_z_rust_tool_processes_csv_and_regenerates_result():
    rng = random.SystemRandom()
    base = rng.randint(6, 45)
    coefficient = rng.choice([1.37, 1.83, 2.41, 2.77, 3.19])
    offset = rng.choice([-8.25, -3.6, 4.15, 9.7])
    noises = [0.17, -0.31, 0.26, -0.08]

    valid_rows = []
    for index, delta in enumerate([0, 3, 8, 14]):
        x = float(base + delta)
        feature_a = x - (index + 1) * 0.4
        feature_b = x + (index + 1) * 0.4
        target = coefficient * x + offset + noises[index]
        valid_rows.append((100 + index, feature_a, feature_b, target))

    lines = ["id,feature_a,feature_b,target"]
    for row in valid_rows:
        lines.append(f"{row[0]},{row[1]:.8f},{row[2]:.8f},{row[3]:.8f}")

    # These rows have extreme targets so accepting any malformed identifier or field
    # materially changes the fitted model.
    lines.extend([
        f",{base}.0,{base}.0,90001.0",
        f"4.0,{base + 1}.0,{base + 1}.0,90002.0",
        f"-1,{base + 2}.0,{base + 2}.0,90003.0",
        f"4294967296,{base + 3}.0,{base + 3}.0,90004.0",
        f"3e0,{base + 4}.0,{base + 4}.0,90005.0",
        f"250,not-a-float,{base + 5}.0,90006.0",
        f"251,{base + 6}.0,{base + 6}.0,not-a-float",
    ])
    DATA_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")

    # Independently derive the expected answer from rows satisfying the instructed schema.
    parsed = []
    for line in lines[1:]:
        fields = line.split(",")
        if len(fields) != 4 or re.fullmatch(r"[0-9]+", fields[0]) is None:
            continue
        identifier = int(fields[0])
        if identifier > 0xFFFFFFFF:
            continue
        try:
            feature_a, feature_b, target = map(float, fields[1:])
        except ValueError:
            continue
        parsed.append(((feature_a + feature_b) / 2.0, target))

    n = len(parsed)
    sum_x = sum(x for x, _ in parsed)
    sum_y = sum(y for _, y in parsed)
    sum_xy = sum(x * y for x, y in parsed)
    sum_x2 = sum(x * x for x, _ in parsed)
    expected_slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
    expected_intercept = (sum_y - expected_slope * sum_x) / n

    RESULT_PATH.unlink(missing_ok=True)
    try:
        proc = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT_PATH / "Cargo.toml")],
            cwd=PROJECT_PATH,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The Rust utility did not finish within 180 seconds.")

    assert proc.returncode == 0, f"Rust utility failed:\n{proc.stdout}"
    assert RESULT_PATH.is_file(), "Running the Rust utility did not generate regression_result.json."

    try:
        result = json.loads(RESULT_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        pytest.fail(f"Generated regression_result.json is invalid JSON: {exc}")

    assert "slope" in result, "Generated JSON is missing the 'slope' key."
    assert "intercept" in result, "Generated JSON is missing the 'intercept' key."
    assert isinstance(result["slope"], (int, float)) and not isinstance(result["slope"], bool)
    assert isinstance(result["intercept"], (int, float)) and not isinstance(result["intercept"], bool)
    assert math.isfinite(result["slope"])
    assert math.isfinite(result["intercept"])
    assert round(result["slope"], 4) == round(expected_slope, 4), (
        f"Expected slope {expected_slope:.4f}, got {result['slope']}"
    )
    assert round(result["intercept"], 4) == round(expected_intercept, 4), (
        f"Expected intercept {expected_intercept:.4f}, got {result['intercept']}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
