#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import random

SOURCE = "/home/user/process.c"
PROCESS = "/home/user/process"
DATA = "/home/user/sensor_data.csv"
RESULTS = "/home/user/results.log"
VERIFIED_PROCESS = "/tmp/verified_process"

with open(DATA, "rb") as f:
    ORIGINAL_DATA = f.read()


def run_program(path):
    subprocess.run([path], check=True, timeout=10)


def test_process_c_exists():
    path = SOURCE
    assert os.path.isfile(path), f"Source file {path} was not created."


def test_process_executable_exists():
    path = PROCESS
    assert os.path.isfile(path), f"Executable {path} was not compiled."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled executable."


def test_source_compiles():
    subprocess.run(
        ["gcc", "-O3", "-o", VERIFIED_PROCESS, SOURCE, "-lm"],
        check=True,
        timeout=20,
    )
    assert os.path.isfile(VERIFIED_PROCESS)
    assert os.access(VERIFIED_PROCESS, os.X_OK)


def test_results_log():
    path = RESULTS
    assert os.path.isfile(path), f"Results log {path} was not created."

    # The submitted executable must actually recreate the output.
    os.remove(path)
    run_program(PROCESS)
    assert os.path.isfile(path), f"Results log {path} was not created by {PROCESS}."

    with open(path, "r") as f:
        content = f.read().strip()

    # We expect exactly 3 lines in a specific format
    # Slope: 3.1415
    # Intercept: -2.7182
    # MSE: 0.0000
    lines = content.splitlines()
    assert len(lines) >= 3, "results.log does not contain enough lines."

    slope_match = re.search(r"Slope:\s*([\d\.\-]+)", content)
    intercept_match = re.search(r"Intercept:\s*([\d\.\-]+)", content)
    mse_match = re.search(r"MSE:\s*([\d\.\-]+)", content)

    assert slope_match is not None, "results.log is missing the 'Slope: [m]' line."
    assert intercept_match is not None, "results.log is missing the 'Intercept: [c]' line."
    assert mse_match is not None, "results.log is missing the 'MSE: [mse]' line."

    slope = float(slope_match.group(1))
    intercept = float(intercept_match.group(1))
    mse = float(mse_match.group(1))

    assert abs(slope - 3.1415) < 1e-3, f"Expected Slope close to 3.1415, got {slope}"
    assert abs(intercept - (-2.7182)) < 1e-3, f"Expected Intercept close to -2.7182, got {intercept}"
    assert abs(mse - 0.0) < 1e-3, f"Expected MSE close to 0.0000, got {mse}"

    assert "Slope: 3.1415" in content, "Slope not formatted to exactly 4 decimal places as 'Slope: 3.1415'."
    assert "Intercept: -2.7182" in content, "Intercept not formatted to exactly 4 decimal places as 'Intercept: -2.7182'."
    assert "MSE: 0.0000" in content, "MSE not formatted to exactly 4 decimal places as 'MSE: 0.0000'."


def ols(points):
    n = len(points)
    mean_x = sum(x for x, _ in points) / n
    mean_y = sum(y for _, y in points) / n
    denom = sum((x - mean_x) ** 2 for x, _ in points)
    slope = sum((x - mean_x) * (y - mean_y) for x, y in points) / denom
    intercept = mean_y - slope * mean_x
    mse = sum((y - (slope * x + intercept)) ** 2 for x, y in points) / n
    return slope, intercept, mse


def test_program_processes_dynamic_csv_data():
    rng = random.SystemRandom()

    try:
        for _ in range(3):
            true_slope = rng.uniform(-4.0, 4.0)
            true_intercept = rng.uniform(-30.0, 30.0)
            clean = []
            rows = []

            for _ in range(25):
                x = rng.uniform(-80.0, 80.0)
                y = true_slope * x + true_intercept + rng.uniform(-3.0, 3.0)
                x_text = f"{x:.6f}"
                y_text = f"{y:.6f}"
                x_value = float(x_text)
                y_value = float(y_text)
                clean.append((x_value, y_value))
                rows.append(f"{x_text},{y_text}")

            # Values exactly at the limits are valid because exclusion is strict.
            clean.extend([(1000.0, 1000.0), (-1000.0, -1000.0)])
            rows.extend(["1000.000000,1000.000000", "-1000.000000,-1000.000000"])

            # These rows must all be discarded.
            rows.extend([
                "NA,5.0",
                "10.0,NA",
                ",7.0",
                "8.0,",
                "1000.0001,0.0",
                "-1000.0001,0.0",
                "0.0,1000.0001",
                "0.0,-1000.0001",
            ])
            rng.shuffle(rows)

            with open(DATA, "w", newline="") as f:
                f.write("X,Y\n")
                f.write("\n".join(rows) + "\n")

            if os.path.exists(RESULTS):
                os.remove(RESULTS)
            run_program(VERIFIED_PROCESS)
            assert os.path.isfile(RESULTS), "The compiled source did not create results.log."

            with open(RESULTS, "r") as f:
                content = f.read().strip()

            match = re.fullmatch(
                r"Slope: (-?\d+\.\d{4})\nIntercept: (-?\d+\.\d{4})\nMSE: (-?\d+\.\d{4})",
                content,
            )
            assert match is not None, "results.log must contain exactly three correctly formatted lines."

            expected = ols(clean)
            expected_text = (
                f"Slope: {expected[0]:.4f}\n"
                f"Intercept: {expected[1]:.4f}\n"
                f"MSE: {expected[2]:.4f}"
            )
            assert content == expected_text, (
                f"Incorrect OLS result for dynamically generated cleaned data.\n"
                f"Expected:\n{expected_text}\nGot:\n{content}"
            )
    finally:
        with open(DATA, "wb") as f:
            f.write(ORIGINAL_DATA)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
