#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import subprocess
import sys
import pytest

SCRIPT_PATH = "/home/user/integration_study.py"
RESULTS_PATH = "/home/user/results.json"


@pytest.fixture(scope="session", autouse=True)
def run_student_script():
    """Execute the submitted script and require it to generate a fresh results file."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is not a regular file."

    if os.path.lexists(RESULTS_PATH):
        if os.path.isdir(RESULTS_PATH) and not os.path.islink(RESULTS_PATH):
            pytest.fail(f"Results path {RESULTS_PATH} is a directory.")
        os.remove(RESULTS_PATH)

    try:
        proc = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("integration_study.py did not finish within 180 seconds.")

    assert proc.returncode == 0, (
        "integration_study.py failed when executed.\n"
        f"stdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}"
    )
    assert os.path.exists(RESULTS_PATH), (
        f"Executing {SCRIPT_PATH} did not create {RESULTS_PATH}."
    )


def test_script_exists():
    """Check that the student's script exists."""
    script_path = "/home/user/integration_study.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."


def test_results_json():
    """Validate the contents of the results.json file."""
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"Results file {results_path} does not exist."

    with open(results_path, 'r') as f:
        try:
            student_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    # Generate expected data using numpy in a subprocess.
    # This ensures we use the exact numpy floating point and random seed behavior.
    expected_script = """
import numpy as np
import json

def f(x): return np.sin(x**2)

true_val = 0.5279172037233621
Ns = [1000, 2000, 4000, 8000, 16000]

def trapz(a, b, N):
    x = np.linspace(a, b, N+1)
    y = f(x)
    dx = (b-a)/N
    return dx * (np.sum(y) - 0.5*y[0] - 0.5*y[-1])

errors = [abs(trapz(0, 5, n) - true_val) for n in Ns]

N = 16000
a, b = 0, 5
x = np.linspace(a, b, N+1)
y = f(x)
dx = (b-a)/N

blocks = []
for i in range(160):
    start = i*100
    end = (i+1)*100
    block_val = dx * (np.sum(y[start:end+1]) - 0.5*y[start] - 0.5*y[end])
    blocks.append(np.float32(block_val))

np.random.seed(42)
sums = []
for _ in range(1000):
    np.random.shuffle(blocks)
    sums.append(float(np.sum(np.array(blocks, dtype=np.float32), dtype=np.float32)))

np.random.seed(42)
means = []
for _ in range(10000):
    resample = np.random.choice(sums, size=len(sums), replace=True)
    means.append(np.mean(resample))

ci = [float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))]

expected_json = {
    "refinement_errors": errors,
    "bootstrap_ci": ci,
    "true_value": true_val
}
print(json.dumps(expected_json))
"""
    proc = subprocess.run(
        [sys.executable, "-c", expected_script],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        pytest.fail(f"Failed to generate expected truth data: {proc.stderr}")

    expected_data = json.loads(proc.stdout)

    # 1. Check true_value
    assert "true_value" in student_data, "Missing 'true_value' in results.json"
    assert math.isclose(student_data["true_value"], expected_data["true_value"], abs_tol=1e-12), \
        f"true_value is incorrect. Expected {expected_data['true_value']}, got {student_data['true_value']}"

    # 2. Check refinement_errors
    assert "refinement_errors" in student_data, "Missing 'refinement_errors' in results.json"
    s_errors = student_data["refinement_errors"]
    e_errors = expected_data["refinement_errors"]
    assert isinstance(s_errors, list) and len(s_errors) == 5, "refinement_errors must be a list of 5 values"
    for i, (s_err, e_err) in enumerate(zip(s_errors, e_errors)):
        assert math.isclose(s_err, e_err, abs_tol=1e-12), \
            f"refinement_errors[{i}] is incorrect. Expected ~{e_err}, got {s_err}"

    # 3. Check bootstrap_ci
    assert "bootstrap_ci" in student_data, "Missing 'bootstrap_ci' in results.json"
    s_ci = student_data["bootstrap_ci"]
    e_ci = expected_data["bootstrap_ci"]
    assert isinstance(s_ci, list) and len(s_ci) == 2, "bootstrap_ci must be a list of 2 values [lower, upper]"
    for i, (s_val, e_val) in enumerate(zip(s_ci, e_ci)):
        assert math.isclose(s_val, e_val, abs_tol=1e-6), \
            f"bootstrap_ci[{i}] is incorrect. Expected ~{e_val}, got {s_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
