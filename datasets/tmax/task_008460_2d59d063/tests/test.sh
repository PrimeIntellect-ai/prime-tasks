#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

SOURCE = Path("/home/user/etl_bayes.cpp")
EXECUTABLE = Path("/home/user/etl_bayes")
MEASUREMENTS = Path("/home/user/measurements.csv")
POSTERIOR = Path("/home/user/posterior.json")
REBUILT_EXECUTABLE = Path("/tmp/etl_bayes_from_source")


@pytest.fixture(scope="session", autouse=True)
def restore_original_files():
    measurements_data = MEASUREMENTS.read_bytes()
    posterior_existed = POSTERIOR.is_file()
    posterior_data = POSTERIOR.read_bytes() if posterior_existed else None
    yield
    MEASUREMENTS.write_bytes(measurements_data)
    if posterior_existed:
        POSTERIOR.write_bytes(posterior_data)
    elif POSTERIOR.exists():
        POSTERIOR.unlink()


def test_cpp_source_exists():
    """Test that the C++ source file exists."""
    assert SOURCE.is_file(), "The C++ source file /home/user/etl_bayes.cpp does not exist."


def test_cpp_executable_exists():
    """Test that the compiled executable exists."""
    assert EXECUTABLE.is_file(), "The compiled executable /home/user/etl_bayes does not exist."
    assert os.access(EXECUTABLE, os.X_OK), "The file /home/user/etl_bayes is not executable."
    assert EXECUTABLE.read_bytes()[:4] == b"\x7fELF", "/home/user/etl_bayes is not a compiled ELF executable."


def test_posterior_json_exists_and_correct():
    """Retain the original final-state check for the supplied CSV."""
    assert POSTERIOR.is_file(), f"The output file {POSTERIOR} does not exist."

    with POSTERIOR.open("r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {POSTERIOR} does not contain valid JSON.")

    assert "posterior_mean" in data, "The JSON output is missing the 'posterior_mean' key."
    assert "posterior_variance" in data, "The JSON output is missing the 'posterior_variance' key."

    expected_mean = 0.75
    expected_variance = 0.25

    assert math.isclose(data["posterior_mean"], expected_mean, abs_tol=1e-4), \
        f"Expected posterior_mean to be {expected_mean}, but got {data['posterior_mean']}."
    assert math.isclose(data["posterior_variance"], expected_variance, abs_tol=1e-4), \
        f"Expected posterior_variance to be {expected_variance}, but got {data['posterior_variance']}."


def test_source_compiles():
    result = subprocess.run(
        ["/usr/bin/g++", "-std=c++17", str(SOURCE), "-o", str(REBUILT_EXECUTABLE)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"The submitted C++ source did not compile:\n{result.stderr}"
    assert REBUILT_EXECUTABLE.is_file() and os.access(REBUILT_EXECUTABLE, os.X_OK)


def expected_from_csv(csv_text):
    values = []
    for row in csv_text.splitlines():
        columns = row.split(",")
        if len(columns) != 3:
            continue
        sensor_id, measurement, status = columns
        if status != "OK" or re.fullmatch(r"[+-]?[0-9]+", sensor_id) is None:
            continue
        if int(sensor_id) <= 0:
            continue
        try:
            value = float(measurement)
        except ValueError:
            continue
        if not math.isfinite(value):
            continue
        values.append(value)

    n = len(values)
    variance = 1.0 / (1.0 + n)
    mean = variance * math.fsum(values)
    return round(mean, 4), round(variance, 4)


def read_and_check_output(expected_mean, expected_variance):
    assert POSTERIOR.is_file(), "Running the executable did not create /home/user/posterior.json."
    try:
        with POSTERIOR.open("r") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The generated posterior.json is invalid JSON: {exc}")

    assert "posterior_mean" in data, "The JSON output is missing the 'posterior_mean' key."
    assert "posterior_variance" in data, "The JSON output is missing the 'posterior_variance' key."
    assert isinstance(data["posterior_mean"], (int, float)) and not isinstance(data["posterior_mean"], bool)
    assert isinstance(data["posterior_variance"], (int, float)) and not isinstance(data["posterior_variance"], bool)
    assert math.isclose(data["posterior_mean"], expected_mean, rel_tol=0, abs_tol=1e-4), \
        f"Expected posterior_mean {expected_mean}, got {data['posterior_mean']}"
    assert math.isclose(data["posterior_variance"], expected_variance, rel_tol=0, abs_tol=1e-4), \
        f"Expected posterior_variance {expected_variance}, got {data['posterior_variance']}"


rng = random.SystemRandom()
random_valid_rows = [
    f"{100 + i},{rng.randint(-9000, 9000) / 1000.0:.3f},OK"
    for i in range(rng.randint(3, 7))
]
random_case = "\n".join(random_valid_rows + [
    "0,500.0,OK",
    "-8,400.0,OK",
    "bad,300.0,OK",
    "999,200.0,FAIL",
    "1000,not-a-number,OK",
    "1001,10.0,OK,extra",
]) + "\n"

CASES = [
    "10,8.0,OK\n3,-2.25,OK\n4,1.0,FAIL\nx,2.0,OK\n5,4.126,OK\n6,2.0,OK,EXTRA\n",
    "0,10.0,OK\n-1,20.0,OK\nA,30.0,OK\n4,text,OK\n5,50.0,FAIL\n",
    "1,1.25,OK\n2,2.5,OKAY\n3,3.75, OK\n4,4oops,OK\n5.5,5.0,OK\n6,6.0,OK\n7,7.0,OK,extra\n",
    random_case,
]


@pytest.mark.parametrize("program", [EXECUTABLE, REBUILT_EXECUTABLE], ids=["submitted-executable", "rebuilt-source"])
@pytest.mark.parametrize("csv_text", CASES, ids=["mixed-rows", "no-valid-rows", "strict-schema", "randomized-values"])
def test_program_processes_csv(program, csv_text):
    expected_mean, expected_variance = expected_from_csv(csv_text)
    MEASUREMENTS.write_text(csv_text)
    if POSTERIOR.exists():
        POSTERIOR.unlink()

    result = subprocess.run(
        [str(program)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, \
        f"{program} exited with status {result.returncode}. stderr:\n{result.stderr}"
    read_and_check_output(expected_mean, expected_variance)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
