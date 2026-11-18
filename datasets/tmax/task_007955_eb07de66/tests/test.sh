#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

import pytest

VENV_PYTHON = "/home/user/venv/bin/python"
FITTER = "/home/user/fitter.py"
RUN_TESTS = "/home/user/run_tests.sh"
REPORT = "/home/user/regression_report.log"
REFERENCE = "/home/user/reference.csv"
DATA_DIR = "/home/user/data"


def test_venv_exists():
    venv_path = "/home/user/venv"
    assert os.path.isdir(venv_path), f"Virtual environment directory {venv_path} is missing."
    assert os.path.isfile(os.path.join(venv_path, "bin", "python")), "Python executable missing in venv."


def test_fitter_script_exists():
    fitter_path = "/home/user/fitter.py"
    assert os.path.isfile(fitter_path), f"Fitter script {fitter_path} is missing."


def test_run_tests_script_exists_and_executable():
    script_path = "/home/user/run_tests.sh"
    assert os.path.isfile(script_path), f"Bash script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Bash script {script_path} is not executable."


def test_regression_report_exists():
    report_path = "/home/user/regression_report.log"
    assert os.path.isfile(report_path), f"Regression report {report_path} is missing."


def test_regression_report_content():
    report_path = "/home/user/regression_report.log"
    assert os.path.isfile(report_path), f"Regression report {report_path} is missing."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "sensor_1: PASS",
        "sensor_2: FAIL",
        "sensor_3: PASS"
    ]

    assert lines == expected_lines, (
        f"Regression report contents do not match expected.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(lines)}"
    )


def write_dataset(path, A, B, C):
    with open(path, "w") as f:
        f.write("t,y\n")
        for i in range(81):
            t = 8.0 * i / 80.0
            y = A * math.exp(-B * t) + C
            f.write(f"{t:.17g},{y:.17g}\n")


def run_command(command):
    return subprocess.run(
        command,
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )


def test_venv_dependencies_are_working():
    result = run_command([
        VENV_PYTHON,
        "-c",
        "import numpy; import scipy; from scipy.optimize import curve_fit; "
        "assert numpy.isfinite(numpy.array([1.0])).all()",
    ])
    assert result.returncode == 0, (
        "The virtual environment cannot import working numpy/scipy dependencies.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_fitter_executes_and_fits_unseen_data(tmp_path):
    # Randomized parameters and filename prevent a precomputed-output placeholder.
    rng = secrets.SystemRandom()
    expected = (
        rng.uniform(2.5, 7.0),
        rng.uniform(0.2, 0.9),
        rng.uniform(-1.0, 1.0),
    )
    data_path = tmp_path / f"unseen_{secrets.token_hex(8)}.txt"
    write_dataset(data_path, *expected)

    result = run_command([VENV_PYTHON, FITTER, str(data_path)])
    assert result.returncode == 0, (
        f"fitter.py failed on a valid unseen dataset.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    fields = result.stdout.split()
    assert len(fields) == 3, f"fitter.py must print exactly three parameters; got: {result.stdout!r}"
    try:
        fitted = tuple(float(value) for value in fields)
    except ValueError as exc:
        pytest.fail(f"fitter.py output is not three numeric parameters: {result.stdout!r}: {exc}")

    assert all(math.isfinite(value) for value in fitted), f"Non-finite fitted values: {fitted}"
    for label, actual, wanted in zip(("A", "B", "C"), fitted, expected):
        assert abs(actual - wanted) < 0.01, (
            f"Incorrect fitted {label}: expected approximately {wanted}, got {actual}"
        )


def test_run_tests_executes_real_regression_logic():
    token = secrets.token_hex(8)
    pass_name = f"verify_a_{token}"
    fail_name = f"verify_b_{token}"
    pass_path = os.path.join(DATA_DIR, pass_name + ".txt")
    fail_path = os.path.join(DATA_DIR, fail_name + ".txt")

    pass_params = (3.7, 0.43, -0.6)
    fail_params = (6.2, 0.71, 0.4)

    with open(REFERENCE, "rb") as f:
        original_reference = f.read()

    restore_result = None
    try:
        write_dataset(pass_path, *pass_params)
        write_dataset(fail_path, *fail_params)

        with open(REFERENCE, "ab") as f:
            if original_reference and not original_reference.endswith(b"\n"):
                f.write(b"\n")
            f.write(
                (f"{pass_name},{pass_params[0]},{pass_params[1]},{pass_params[2]}\n"
                 f"{fail_name},{fail_params[0] + 0.2},{fail_params[1]},{fail_params[2]}\n").encode()
            )

        if os.path.exists(REPORT):
            os.remove(REPORT)
        result = run_command([RUN_TESTS])
        assert result.returncode == 0, (
            f"run_tests.sh failed.\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(REPORT), "run_tests.sh did not generate regression_report.log"

        with open(REPORT) as f:
            actual = [line.strip() for line in f if line.strip()]

        expected = sorted([
            "sensor_1: PASS",
            "sensor_2: FAIL",
            "sensor_3: PASS",
            f"{pass_name}: PASS",
            f"{fail_name}: FAIL",
        ])
        assert actual == expected, (
            "run_tests.sh did not fit and classify the dynamically added sensors correctly, "
            "or did not sort the report.\n"
            f"Expected: {expected}\nGot: {actual}"
        )
    finally:
        with open(REFERENCE, "wb") as f:
            f.write(original_reference)
        for path in (pass_path, fail_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        try:
            os.remove(REPORT)
        except FileNotFoundError:
            pass
        restore_result = run_command([RUN_TESTS])

    assert restore_result.returncode == 0, (
        "run_tests.sh failed after restoring the supplied inputs.\n"
        f"stdout: {restore_result.stdout}\nstderr: {restore_result.stderr}"
    )
    with open(REPORT) as f:
        restored_lines = [line.strip() for line in f if line.strip()]
    assert restored_lines == ["sensor_1: PASS", "sensor_2: FAIL", "sensor_3: PASS"]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
