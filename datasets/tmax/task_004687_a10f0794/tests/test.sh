#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest
import numpy as np
from scipy.stats import bootstrap

HOME = "/home/user"
OBS = os.path.join(HOME, "observations.txt")
SOURCE = os.path.join(HOME, "integrator.c")
DERIV = os.path.join(HOME, "derivatives.txt")
SCRIPT = os.path.join(HOME, "calc_ci.py")
CI = os.path.join(HOME, "ci.txt")
EXE = "/tmp/submission_integrator"


def expected_derivatives(data):
    expected = []
    for i in range(100):
        row = data[i * 5:(i + 1) * 5]
        y = sum(row) / 5.0
        for _ in range(1000):
            y += 0.001 * (-y * y)
        expected.append(-y * y)
    return expected


def read_and_check_derivatives(expected):
    assert os.path.isfile(DERIV), f"Missing file: {DERIV}"
    with open(DERIV, "r") as f:
        actual_lines = f.read().strip().split()
    assert len(actual_lines) == 100, f"Expected 100 lines in {DERIV}, found {len(actual_lines)}"
    for i, (actual_str, wanted) in enumerate(zip(actual_lines, expected)):
        try:
            actual = float(actual_str)
        except ValueError:
            pytest.fail(f"Line {i+1} in {DERIV} is not a valid float: {actual_str}")
        assert abs(actual - wanted) < 1e-4, \
            f"Derivative mismatch at index {i}. Expected {wanted}, got {actual}"


def run_checked(command, timeout=120):
    result = subprocess.run(
        command, cwd=HOME, capture_output=True, text=True, timeout=timeout
    )
    assert result.returncode == 0, \
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def expected_ci(values):
    arr = np.asarray(values, dtype=float)
    result = bootstrap(
        (arr,), np.mean,
        confidence_level=0.95,
        n_resamples=9999,
        method='percentile',
        random_state=np.random.default_rng(42),
    )
    return f"[{result.confidence_interval.low:.4f}, {result.confidence_interval.high:.4f}]"


@pytest.fixture(scope="session", autouse=True)
def execute_and_exercise_pipeline():
    assert os.path.isfile(SOURCE), f"Missing C source: {SOURCE}"
    assert os.path.isfile(SCRIPT), f"Missing Python script: {SCRIPT}"

    run_checked(["gcc", "-O2", "-std=c11", SOURCE, "-o", EXE, "-lm"])
    assert os.path.isfile(EXE), "Compilation did not produce an executable"

    with open(OBS, "rb") as f:
        original_observations = f.read()

    # Exercise the compiled C artifact on verifier-generated observations rather
    # than trusting artifacts left by the agent.
    challenge_rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    challenge_data = challenge_rng.uniform(0.5, 2.5, 500).tolist()
    try:
        with open(OBS, "w") as f:
            f.write(" ".join(repr(x) for x in challenge_data))
        if os.path.exists(DERIV):
            os.remove(DERIV)
        run_checked([EXE], timeout=30)
        read_and_check_derivatives(expected_derivatives(challenge_data))
    finally:
        with open(OBS, "wb") as f:
            f.write(original_observations)

    # Run the C program on the real observations to regenerate the required file.
    if os.path.exists(DERIV):
        os.remove(DERIV)
    run_checked([EXE], timeout=30)

    # Exercise calc_ci.py on fresh, verifier-generated derivative data.
    ci_rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    synthetic_derivatives = ci_rng.normal(-0.4, 0.08, 100)
    try:
        with open(DERIV, "w") as f:
            f.write("\n".join(repr(float(x)) for x in synthetic_derivatives) + "\n")
        if os.path.exists(CI):
            os.remove(CI)
        run_checked(["python3", SCRIPT])
        assert os.path.isfile(CI), f"Running {SCRIPT} did not create {CI}"
        with open(CI, "r") as f:
            actual = f.read().strip()
        wanted = expected_ci(synthetic_derivatives)
        assert actual == wanted, \
            f"calc_ci.py failed generated-input test. Expected '{wanted}', got '{actual}'"
    finally:
        # Leave the requested pipeline outputs regenerated from the real input.
        if os.path.exists(DERIV):
            os.remove(DERIV)
        run_checked([EXE], timeout=30)
        if os.path.exists(CI):
            os.remove(CI)
        run_checked(["python3", SCRIPT])


def test_derivatives_txt_exists_and_correct():
    obs_path = "/home/user/observations.txt"
    deriv_path = "/home/user/derivatives.txt"

    assert os.path.isfile(deriv_path), f"Missing file: {deriv_path}"

    with open(obs_path, "r") as f:
        data = [float(x) for x in f.read().split()]

    assert len(data) == 500, "observations.txt does not contain 500 floats."

    expected_dy_dt = []
    for i in range(100):
        row = data[i*5:(i+1)*5]
        y = sum(row) / 5.0
        dt = 0.001
        for _ in range(1000):
            y += dt * (-y * y)
        expected_dy_dt.append(-y * y)

    with open(deriv_path, "r") as f:
        actual_lines = f.read().strip().split()

    assert len(actual_lines) == 100, f"Expected 100 lines in {deriv_path}, found {len(actual_lines)}"

    for i, (actual_str, expected) in enumerate(zip(actual_lines, expected_dy_dt)):
        try:
            actual = float(actual_str)
        except ValueError:
            pytest.fail(f"Line {i+1} in {deriv_path} is not a valid float: {actual_str}")

        assert abs(actual - expected) < 1e-4, f"Derivative mismatch at index {i}. Expected {expected}, got {actual}"


def test_calc_ci_py_exists():
    script_path = "/home/user/calc_ci.py"
    assert os.path.isfile(script_path), f"Missing Python script: {script_path}"


def test_ci_txt_exists_and_correct():
    ci_path = "/home/user/ci.txt"
    assert os.path.isfile(ci_path), f"Missing file: {ci_path}"

    canonical_script = """
import numpy as np
from scipy.stats import bootstrap

with open('/home/user/observations.txt', 'r') as f:
    data = np.array([float(x) for x in f.read().split()])

ic = data.reshape(100, 5).mean(axis=1)

dt = 0.001
y = ic.copy()
for _ in range(1000):
    y += dt * (-y*y)

dy_dt = -y*y

rng = np.random.default_rng(42)
res = bootstrap((dy_dt,), np.mean, confidence_level=0.95, n_resamples=9999, method='percentile', random_state=rng)

print(f"[{res.confidence_interval.low:.4f}, {res.confidence_interval.high:.4f}]")
"""
    result = subprocess.run(
        ['python3', '-c', canonical_script],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Failed to compute canonical CI: {result.stderr}"
    expected_ci_string = result.stdout.strip()

    with open(ci_path, "r") as f:
        actual_ci = f.read().strip()

    assert actual_ci == expected_ci_string, f"CI mismatch in {ci_path}. Expected '{expected_ci_string}', got '{actual_ci}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
