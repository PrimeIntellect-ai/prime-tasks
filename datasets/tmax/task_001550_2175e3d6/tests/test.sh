#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

import pytest

RAW = "/home/user/raw_sensors.csv"
SOURCE = "/home/user/etl_processor.cpp"
EXECUTABLE = "/home/user/etl_processor"
PROCESSED = "/home/user/processed_features.csv"
INVALID = "/home/user/invalid_rows.log"


def expected_from_raw():
    expected_processed = []
    expected_invalid = []

    with open(RAW, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split(",")
            if len(parts) != 32:
                expected_invalid.append(line)
                continue

            sensor_id_str = parts[0]
            try:
                int(sensor_id_str)
            except ValueError:
                expected_invalid.append(line)
                continue

            timestamp = parts[1]
            try:
                readings = [float(x) for x in parts[2:]]
            except ValueError:
                expected_invalid.append(line)
                continue

            dim1 = sum(readings[0:10]) / 10.0
            dim2 = max(readings[10:20])
            dim3 = min(readings[20:30])

            if (math.isnan(dim1) or math.isnan(dim2) or math.isnan(dim3) or
                    math.isinf(dim1) or math.isinf(dim2) or math.isinf(dim3)):
                expected_invalid.append(line)
                continue

            dim1 = max(-100.0, min(100.0, dim1))
            dim2 = max(-100.0, min(100.0, dim2))
            dim3 = max(-100.0, min(100.0, dim3))
            expected_processed.append(
                f"{sensor_id_str},{timestamp},{dim1:.4f},{dim2:.4f},{dim3:.4f}"
            )

    return expected_processed, expected_invalid


def make_input():
    rng = secrets.SystemRandom()
    timestamp = f"2026-09-11T12:{rng.randrange(0, 60):02d}:{rng.randrange(0, 60):02d}"

    first = [rng.randrange(-90, 91) for _ in range(30)]
    mixed = [rng.randrange(-75, 76) for _ in range(30)]
    clamped = [150] * 10 + [rng.randrange(101, 201) for _ in range(10)] + [rng.randrange(-200, -100) for _ in range(10)]

    return [
        f"{rng.randrange(1000, 9000)},{timestamp}," + ",".join(map(str, first)),
        "bad-id,2026-09-11T12:00:01," + ",".join(["1"] * 30),
        "7,2026-09-11T12:00:02," + ",".join(["2"] * 29),
        "8,2026-09-11T12:00:03," + ",".join(["3"] * 29) + ",not-a-float",
        f"{rng.randrange(1000, 9000)},2026-09-11T12:00:04," + ",".join(map(str, clamped)),
        "9,2026-09-11T12:00:05,nan," + ",".join(["4"] * 29),
        "10,2026-09-11T12:00:06,inf," + ",".join(["5"] * 29),
        f"{rng.randrange(1000, 9000)},2026-09-11T12:00:07," + ",".join(map(str, mixed)),
    ]


def run_case(program):
    with open(RAW, "w") as f:
        for row in make_input():
            f.write(row + "\n")

    for path in (PROCESSED, INVALID):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run([program], cwd="/home/user", check=True, timeout=15)
    assert os.path.isfile(PROCESSED), f"{PROCESSED} is missing after execution."
    assert os.path.isfile(INVALID), f"{INVALID} is missing after execution."

    expected_processed, expected_invalid = expected_from_raw()
    with open(PROCESSED, "r") as f:
        actual_processed = [line.strip() for line in f if line.strip()]
    with open(INVALID, "r") as f:
        actual_invalid = [line.strip() for line in f if line.strip()]

    assert actual_processed == expected_processed
    assert actual_invalid == expected_invalid


@pytest.fixture(scope="session", autouse=True)
def build_and_exercise_pipeline():
    assert os.path.isfile(RAW), f"{RAW} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled executable."

    rebuilt = "/tmp/verifier_etl_processor"
    subprocess.run(
        ["g++", "-O3", SOURCE, "-o", rebuilt],
        check=True,
        timeout=30,
    )

    # Exercise both the submitted executable and a fresh build of the submitted source.
    run_case(EXECUTABLE)
    run_case(rebuilt)


def test_output_files_exist():
    """Verify that the expected output files exist."""
    assert os.path.isfile(PROCESSED), f"{PROCESSED} is missing."
    assert os.path.isfile(INVALID), f"{INVALID} is missing."


def test_processed_features_content():
    """Verify the content of processed_features.csv matches the expected logic."""
    expected_processed, _ = expected_from_raw()

    with open(PROCESSED, "r") as f:
        actual_processed = [line.strip() for line in f if line.strip()]

    assert actual_processed == expected_processed, (
        f"processed_features.csv content is incorrect.\n"
        f"Expected:\n{chr(10).join(expected_processed)}\n"
        f"Actual:\n{chr(10).join(actual_processed)}"
    )


def test_invalid_rows_content():
    """Verify the content of invalid_rows.log matches the expected logic."""
    _, expected_invalid = expected_from_raw()

    with open(INVALID, "r") as f:
        actual_invalid = [line.strip() for line in f if line.strip()]

    assert actual_invalid == expected_invalid, (
        f"invalid_rows.log content is incorrect.\n"
        f"Expected:\n{chr(10).join(expected_invalid)}\n"
        f"Actual:\n{chr(10).join(actual_invalid)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
