#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import pytest

SOURCE = "/home/user/rolling_stat.c"
EXECUTABLE = "/home/user/rolling_stat"
OUTPUT = "/home/user/processed_data.csv"


def run_program(path, rows):
    input_data = "".join(
        f"{timestamp},{sensor_id},{status},{reading}\n"
        for timestamp, sensor_id, status, reading in rows
    )
    result = subprocess.run(
        [path],
        input=input_data,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    return result.stdout.splitlines()


def expected_rolling(rows):
    expected = []
    current_sensor = None
    window = []
    for timestamp, sensor_id, _status, reading in rows:
        if sensor_id != current_sensor:
            current_sensor = sensor_id
            window = []
        window.append(float(reading))
        window = window[-3:]
        expected.append(f"{sensor_id},{timestamp},{sum(window) / len(window):.2f}")
    return expected


@pytest.fixture(scope="session")
def rebuilt_program(tmp_path_factory):
    destination = tmp_path_factory.mktemp("build") / "rolling_stat_rebuilt"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", str(destination)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, (
        f"The submitted C source did not compile. stderr: {result.stderr}"
    )
    return str(destination)


def test_c_source_code_exists():
    path = SOURCE
    assert os.path.exists(path), f"C source file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."


def test_c_executable_exists():
    path = EXECUTABLE
    assert os.path.exists(path), f"Compiled executable {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled native executable."


def test_processed_data_output():
    path = OUTPUT
    assert os.path.exists(path), f"Output file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

    expected_lines = [
        "S1,10,10.00",
        "S1,30,15.00",
        "S1,50,20.00",
        "S1,60,30.00",
        "S2,5,25.00",
        "S2,15,15.00",
        "S2,25,15.00"
    ]

    with open(path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {path} do not match the expected processed output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def test_executable_reproduces_filtered_sorted_pipeline():
    rows = []
    pattern = re.compile(r"ERROR-[0-9A-F]{3}")
    with open("/home/user/sensor_data.csv", "r") as f:
        for line in f:
            timestamp, sensor_id, status, reading = line.rstrip("\n").split(",")
            if pattern.fullmatch(status):
                rows.append((int(timestamp), sensor_id, status, reading))
    rows.sort(key=lambda row: (row[1], row[0]))

    expected = expected_rolling(rows)
    assert run_program(EXECUTABLE, rows) == expected
    with open(OUTPUT, "r") as f:
        actual_file = [line.strip() for line in f if line.strip()]
    assert actual_file == expected


def test_installed_and_rebuilt_programs_generalize(rebuilt_program):
    rng = random.SystemRandom()
    sensor_ids = sorted({
        "T" + "".join(rng.choice(string.ascii_uppercase + string.digits) for _ in range(7))
        for _ in range(8)
    })
    assert len(sensor_ids) >= 4

    rows = []
    for sensor_id in sensor_ids[:4]:
        timestamps = sorted(rng.sample(range(1000, 50000), rng.randint(4, 8)))
        for timestamp in timestamps:
            reading = rng.randint(0, 900)
            rows.append((timestamp, sensor_id, "ERROR-A1F", str(reading)))

    expected = expected_rolling(rows)
    for program in (EXECUTABLE, rebuilt_program):
        actual = run_program(program, rows)
        assert actual == expected, (
            f"{program} failed rolling-window behavior on independently generated input.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
