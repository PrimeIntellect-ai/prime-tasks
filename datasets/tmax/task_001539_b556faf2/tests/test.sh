#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile
import time

import pytest
import requests

C_FILE = "/home/user/ode_solver.c"
EXE_FILE = "/home/user/ode_solver"
URL = "http://127.0.0.1:8080/predict"
HEADERS = {"Authorization": "Bearer ODE-FIT-2024"}
NUMBER_RE = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?")


def expected_displacement(t, x0, v0):
    omega_n = 2.0
    zeta = 0.1
    omega_d = omega_n * math.sqrt(1 - zeta**2)
    c1 = x0
    c2 = (v0 + zeta * omega_n * x0) / omega_d
    return math.exp(-zeta * omega_n * t) * (
        c1 * math.cos(omega_d * t) + c2 * math.sin(omega_d * t)
    )


def assert_close(actual, case):
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool), \
        f"Prediction is not numeric: {actual!r}"
    assert math.isfinite(float(actual)), f"Prediction is not finite: {actual!r}"
    expected = expected_displacement(case["t"], case["x0"], case["v0"])
    tolerance = max(0.05 * abs(expected), 1e-3)
    assert math.isclose(float(actual), expected, abs_tol=tolerance), \
        f"For parameters {case}, expected x ≈ {expected:.4f}, but got {actual} (tolerance: +/- 5%)"


def random_cases(count):
    rng = secrets.SystemRandom()
    result = []
    while len(result) < count:
        case = {
            "t": rng.uniform(0.05, 6.5),
            "x0": rng.uniform(-220.0, 220.0),
            "v0": rng.uniform(-140.0, 140.0),
        }
        # Avoid accidental near-zero answers, where video-fitting noise would
        # make a relative comparison unnecessarily brittle.
        if abs(expected_displacement(**case)) >= 2.0:
            result.append(case)
    return result


def run_solver(path, case):
    proc = subprocess.run(
        [path, str(case["x0"]), str(case["v0"]), str(case["t"])],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert proc.returncode == 0, f"Solver failed for {case}: {proc.stderr}"
    output = proc.stdout.strip()
    assert NUMBER_RE.fullmatch(output), \
        f"Solver must output only one floating-point number, got: {proc.stdout!r}"
    value = float(output)
    assert math.isfinite(value), f"Solver returned a non-finite value: {output}"
    return value


def test_ode_solver_files_exist():
    assert os.path.exists(C_FILE), f"C source file {C_FILE} is missing."
    assert os.path.isfile(C_FILE), f"C source path {C_FILE} is not a file."
    assert os.path.exists(EXE_FILE), f"Executable {EXE_FILE} is missing."
    assert os.path.isfile(EXE_FILE), f"Executable path {EXE_FILE} is not a file."
    assert os.access(EXE_FILE, os.X_OK), f"File {EXE_FILE} is not executable."
    with open(EXE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXE_FILE} is not a compiled ELF executable."


def test_ode_solver_executes_and_source_builds():
    cases = random_cases(10)

    for case in cases:
        assert_close(run_solver(EXE_FILE, case), case)

    fd, rebuilt = tempfile.mkstemp(prefix="rebuilt_ode_solver_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt)
    try:
        build = subprocess.run(
            ["gcc", "-O2", C_FILE, "-o", rebuilt, "-lm"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert build.returncode == 0, f"C source does not compile: {build.stderr}"
        for case in cases[:5]:
            assert_close(run_solver(rebuilt, case), case)
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)


def test_api_unauthorized():
    payload = {"t": 3.5, "x0": 100.0, "v0": -50.0}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API server: {e}")
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized, got {response.status_code}"


def test_api_predict():
    # Preserve the original cases and add unpredictable cases so fixed response
    # tables cannot satisfy the API contract.
    cases = [
        {"t": 3.5, "x0": 100.0, "v0": -50.0},
        {"t": 1.0, "x0": 50.0, "v0": 0.0},
        {"t": 5.0, "x0": -50.0, "v0": 20.0},
    ] + random_cases(10)

    for case in cases:
        try:
            response = requests.post(URL, json=case, headers=HEADERS, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to API server: {e}")

        assert response.status_code == 200, \
            f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {response.text}")
        assert "x" in data, f"Response JSON missing 'x' key: {data}"
        assert_close(data["x"], case)


def test_api_invokes_compiled_solver():
    # Temporarily substitute a probe at the required executable path. A conforming
    # API must execute it and return its output using x0, v0, t argument order.
    token = secrets.token_hex(8)
    backup = f"/tmp/ode_solver_backup_{token}"
    log_path = f"/tmp/ode_solver_args_{token}"
    sentinel = secrets.SystemRandom().uniform(10000.0, 20000.0)
    case = {
        "t": secrets.SystemRandom().uniform(0.2, 4.0),
        "x0": secrets.SystemRandom().uniform(-100.0, 100.0),
        "v0": secrets.SystemRandom().uniform(-80.0, 80.0),
    }

    os.replace(EXE_FILE, backup)
    try:
        with open(EXE_FILE, "w") as f:
            f.write("#!/bin/sh\n")
            f.write(f"printf '%s\\n' \"$@\" > {log_path}\n")
            f.write(f"printf '%.17g\\n' {sentinel!r}\n")
        os.chmod(EXE_FILE, 0o755)

        response = requests.post(URL, json=case, headers=HEADERS, timeout=5)
        assert response.status_code == 200, \
            f"Expected 200 from solver probe, got {response.status_code}: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Probe response is not valid JSON: {response.text}")
        assert "x" in data, f"Probe response JSON missing 'x': {data}"
        assert math.isclose(float(data["x"]), sentinel, rel_tol=1e-12, abs_tol=1e-9), \
            "API did not return the output of /home/user/ode_solver"

        for _ in range(20):
            if os.path.exists(log_path):
                break
            time.sleep(0.05)
        assert os.path.exists(log_path), "API did not invoke /home/user/ode_solver"
        with open(log_path) as f:
            args = [line.strip() for line in f if line.strip()]
        assert len(args) == 3, f"Expected solver arguments x0 v0 t, got: {args}"
        actual_args = [float(value) for value in args]
        expected_args = [case["x0"], case["v0"], case["t"]]
        for actual, expected in zip(actual_args, expected_args):
            assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), \
                f"API passed incorrect solver arguments: {actual_args}, expected {expected_args}"
    finally:
        if os.path.exists(EXE_FILE):
            os.unlink(EXE_FILE)
        os.replace(backup, EXE_FILE)
        if os.path.exists(log_path):
            os.unlink(log_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
