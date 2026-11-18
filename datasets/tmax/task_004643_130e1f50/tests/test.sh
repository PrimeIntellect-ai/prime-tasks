#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import math
import re
import secrets

CSV_PATH = "/home/user/sensor_data.csv"
SOURCE_PATH = "/home/user/linear_regression.c"
SCRIPT_PATH = "/home/user/evaluate.sh"
MODEL_PATH = "/home/user/lr_model"
JSON_PATH = "/home/user/model_metrics.json"


def test_c_source_exists():
    assert os.path.isfile(SOURCE_PATH), "C program /home/user/linear_regression.c does not exist."


def test_evaluate_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Bash script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Bash script {SCRIPT_PATH} is not executable."


def test_evaluate_script_runs_and_creates_json():
    # Remove the JSON file if it exists to ensure the script creates it
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    result = subprocess.run(
        [SCRIPT_PATH], capture_output=True, text=True, cwd="/home/user", timeout=20
    )
    assert result.returncode == 0, (
        f"evaluate.sh failed with return code {result.returncode}.\nStderr: {result.stderr}"
    )
    assert os.path.isfile(JSON_PATH), f"JSON file {JSON_PATH} was not created by the script."


def test_json_content():
    assert os.path.isfile(JSON_PATH), f"JSON file {JSON_PATH} does not exist."

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {JSON_PATH} does not contain valid JSON."

    assert "model" in data, "Key 'model' missing in JSON."
    assert data["model"] == "linear_regression", f"Expected model name 'linear_regression', got {data['model']}"

    assert "parameters" in data, "Key 'parameters' missing in JSON."
    assert "slope" in data["parameters"], "Key 'slope' missing in parameters."
    assert "intercept" in data["parameters"], "Key 'intercept' missing in parameters."

    assert "evaluation" in data, "Key 'evaluation' missing in JSON."
    assert "mse" in data["evaluation"], "Key 'mse' missing in evaluation."

    slope = float(data["parameters"]["slope"])
    intercept = float(data["parameters"]["intercept"])
    mse = float(data["evaluation"]["mse"])

    assert math.isclose(slope, 2.01, abs_tol=1e-3), f"Expected slope around 2.01, got {slope}"
    assert math.isclose(intercept, 0.03, abs_tol=1e-3), f"Expected intercept around 0.03, got {intercept}"
    assert math.isclose(mse, 0.0102, abs_tol=1e-3), f"Expected mse around 0.0102, got {mse}"


def expected_metrics(points):
    n = len(points)
    mean_x = sum(x for x, _ in points) / n
    mean_y = sum(y for _, y in points) / n
    denominator = sum((x - mean_x) ** 2 for x, _ in points)
    slope = sum((x - mean_x) * (y - mean_y) for x, y in points) / denominator
    intercept = mean_y - slope * mean_x
    mse = sum((y - (slope * x + intercept)) ** 2 for x, y in points) / n
    return slope, intercept, mse


def read_metrics_json():
    with open(JSON_PATH, "r") as f:
        data = json.load(f)
    assert set(data.keys()) == {"model", "parameters", "evaluation"}
    assert data["model"] == "linear_regression"
    assert isinstance(data["parameters"], dict)
    assert isinstance(data["evaluation"], dict)
    assert set(data["parameters"].keys()) == {"slope", "intercept"}
    assert set(data["evaluation"].keys()) == {"mse"}
    return (
        float(data["parameters"]["slope"]),
        float(data["parameters"]["intercept"]),
        float(data["evaluation"]["mse"]),
    )


def test_program_and_pipeline_on_runtime_generated_data():
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    verifier_binary = "/tmp/verifier_lr_model"
    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", verifier_binary, "-lm"],
        capture_output=True, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        "linear_regression.c did not compile with gcc.\n" + compile_result.stderr
    )

    try:
        for _ in range(3):
            count = 6 + secrets.randbelow(4)
            start = 1 + secrets.randbelow(20)
            step = 1 + secrets.randbelow(5)
            base_slope = 0.5 + secrets.randbelow(5000) / 1000.0
            base_intercept = 1.0 + secrets.randbelow(5000) / 1000.0
            points = []
            for i in range(count):
                x = float(start + i * step)
                noise = (secrets.randbelow(1201) - 600) / 1000.0
                y = base_slope * x + base_intercept + noise
                # Compute expectations from exactly the decimal values written to disk.
                points.append((float(f"{x:.6f}"), float(f"{y:.6f}")))

            with open(CSV_PATH, "w") as f:
                f.write("x,y\n")
                for x, y in points:
                    f.write(f"{x:.6f},{y:.6f}\n")

            expected = expected_metrics(points)
            expected_output = (
                f"Slope: {expected[0]:.4f}\n"
                f"Intercept: {expected[1]:.4f}\n"
                f"MSE: {expected[2]:.4f}\n"
            )

            direct = subprocess.run(
                [verifier_binary], capture_output=True, text=True,
                cwd="/home/user", timeout=10
            )
            assert direct.returncode == 0, (
                f"Compiled C program failed with return code {direct.returncode}.\n"
                f"Stderr: {direct.stderr}"
            )
            assert direct.stdout == expected_output, (
                "Compiled C program output was not in the required format or contained "
                f"incorrect values.\nExpected:\n{expected_output}Got:\n{direct.stdout}"
            )

            for path in (MODEL_PATH, JSON_PATH):
                if os.path.lexists(path):
                    os.remove(path)

            result = subprocess.run(
                [SCRIPT_PATH], capture_output=True, text=True,
                cwd="/home/user", timeout=20
            )
            assert result.returncode == 0, (
                f"evaluate.sh failed on generated input.\nStderr: {result.stderr}"
            )
            assert os.path.isfile(MODEL_PATH), "evaluate.sh did not create /home/user/lr_model."
            assert os.access(MODEL_PATH, os.X_OK), "/home/user/lr_model is not executable."
            with open(MODEL_PATH, "rb") as f:
                assert f.read(4) == b"\x7fELF", "lr_model is not a compiled executable."
            assert os.path.isfile(JSON_PATH), "evaluate.sh did not create model_metrics.json."

            actual = read_metrics_json()
            rounded_expected = tuple(float(f"{value:.4f}") for value in expected)
            for name, got, want in zip(("slope", "intercept", "mse"), actual, rounded_expected):
                assert math.isclose(got, want, rel_tol=0.0, abs_tol=1e-9), (
                    f"Generated-data {name} should be {want:.4f}, got {got}"
                )
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if os.path.exists(verifier_binary):
            os.remove(verifier_binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
