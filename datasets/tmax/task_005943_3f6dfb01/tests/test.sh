#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pwd
import re
import secrets
import subprocess

import pytest

EXECUTABLE = "/home/user/prepare_data"
SOURCE = "/home/user/prepare_data.cpp"
RAW_DATA = "/home/user/raw_data.csv"
FEATURES = "/home/user/features_output.csv"
MSE_FILE = "/home/user/mse.txt"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}. Did you compile the C++ script?"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "prepare_data must be a compiled executable."


def test_features_output():
    assert os.path.isfile(FEATURES), f"Output file not found at {FEATURES}. Did you run the executable?"

    with open(FEATURES, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 6, f"Expected 6 lines in {FEATURES} (1 header + 5 rows), found {len(lines)}"
    assert lines[0] == "x,f1,f2,y_pred", "Header in features_output.csv is incorrect"
    assert "1,0.2,0.04,1.08" in lines[1], f"Row 1 incorrect. Expected '1,0.2,0.04,1.08', got '{lines[1]}'"
    assert "2,0.4,0.16,2.32" in lines[2], f"Row 2 incorrect. Expected '2,0.4,0.16,2.32', got '{lines[2]}'"
    assert "3,0.6,0.36,3.72" in lines[3], f"Row 3 incorrect. Expected '3,0.6,0.36,3.72', got '{lines[3]}'"
    assert "4,0.8,0.64,5.28" in lines[4], f"Row 4 incorrect. Expected '4,0.8,0.64,5.28', got '{lines[4]}'"
    assert "5,1,1,7" in lines[5], f"Row 5 incorrect. Expected '5,1,1,7', got '{lines[5]}'"


def test_mse_output():
    assert os.path.isfile(MSE_FILE), f"Output file not found at {MSE_FILE}. Did you run the executable?"

    with open(MSE_FILE, "r") as f:
        content = f.read().strip()

    assert content.startswith("MSE:"), "mse.txt does not start with 'MSE:'"
    try:
        mse_value = float(content.split("MSE:")[1].strip())
    except ValueError:
        pytest.fail(f"Could not parse a float value from mse.txt content: '{content}'")

    assert mse_value == 0.0, f"Expected MSE to be 0.0, but got {mse_value}. The bug in the C++ script might not be fully fixed."


def run_as_user(path):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    result = subprocess.run(
        [path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10, preexec_fn=demote
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}. stderr: {result.stderr}"
    )


def exercise(executable, rows):
    with open(RAW_DATA, "w") as f:
        f.write("x,y\n")
        for x, y in rows:
            f.write(f"{x},{y:.2f}\n")
    os.chmod(RAW_DATA, 0o666)

    for path in (FEATURES, MSE_FILE):
        if os.path.lexists(path):
            os.remove(path)

    run_as_user(executable)
    assert os.path.isfile(FEATURES), "Running the executable did not create features_output.csv"
    assert os.path.isfile(MSE_FILE), "Running the executable did not create mse.txt"

    with open(FEATURES, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines[0] == "x,f1,f2,y_pred"
    assert len(lines) == len(rows) + 1

    expected_mse = 0.0
    for line, (x, y) in zip(lines[1:], rows):
        fields = line.split(",")
        assert len(fields) == 4, f"Malformed feature row: {line}"
        actual_x = int(fields[0])
        f1, f2, prediction = map(float, fields[1:])
        expected_f1 = x / 5.0
        expected_f2 = expected_f1 * expected_f1
        expected_prediction = 5.0 * expected_f1 + 2.0 * expected_f2
        assert actual_x == x
        assert math.isclose(f1, expected_f1, rel_tol=3e-5, abs_tol=1e-6)
        assert math.isclose(f2, expected_f2, rel_tol=3e-5, abs_tol=1e-6)
        assert math.isclose(prediction, expected_prediction, rel_tol=3e-5, abs_tol=1e-6)
        expected_mse += (expected_prediction - y) ** 2

    expected_mse /= len(rows)
    with open(MSE_FILE, "r") as f:
        content = f.read().strip()
    match = re.fullmatch(r"MSE:\s*([-+0-9.eE]+)", content)
    assert match, f"Incorrect MSE output format: {content!r}"
    actual_mse = float(match.group(1))
    assert math.isclose(actual_mse, expected_mse, rel_tol=3e-5, abs_tol=1e-5), (
        f"Expected MSE {expected_mse}, got {actual_mse}"
    )


def random_rows():
    rng = secrets.SystemRandom()
    xs = rng.sample([x for x in range(-19, 20) if x % 5 != 0], 8)
    return [(x, rng.randint(-300, 500) / 20.0) for x in xs]


def test_fixed_source_and_executable_process_unseen_data():
    assert os.path.isfile(SOURCE), f"Source file not found at {SOURCE}"
    rebuilt = "/tmp/prepare_data_from_source"
    result = subprocess.run(
        ["g++", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"The modified source does not compile: {result.stderr}"

    # Test both the source rebuilt by the verifier and the submitted executable
    # on independently generated data unavailable while the agent was running.
    exercise(rebuilt, random_rows())
    exercise(EXECUTABLE, random_rows())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
