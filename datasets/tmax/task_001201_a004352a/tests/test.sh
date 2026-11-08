#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import math
import os
import random
import re
import shlex
import struct
import subprocess

SCRIPT_PATH = "/home/user/anomaly_detector.py"
DATA_PATH = "/home/user/telemetry.b64"
OUTPUT_PATH = "/home/user/fixed_variances.txt"


def run_artifact():
    assert os.path.isfile(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"

    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()

    if first_line.startswith("#!"):
        command = shlex.split(first_line[2:].strip()) + [SCRIPT_PATH]
    else:
        command = ["python3", SCRIPT_PATH]

    result = subprocess.run(
        command,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"The repaired artifact exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_repaired_script_runs_on_supplied_telemetry():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_artifact()


def test_fixed_variances_file_exists():
    """Check that the fixed_variances.txt file was created."""
    assert os.path.isfile(OUTPUT_PATH), (
        f"Missing file: {OUTPUT_PATH}. Did you write the output to the correct path?"
    )


def test_fixed_variances_content():
    """Check that the fixed_variances.txt file contains the correct output."""
    assert os.path.isfile(OUTPUT_PATH), "Missing file: /home/user/fixed_variances.txt"

    with open(OUTPUT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "1: 0.0200",
        "2: 0.1067",
    ]

    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines, but found {len(lines)}."
    )
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} mismatch. Expected '{expected}', but got '{actual}'."
        )


def test_script_parses_double_records_and_computes_stable_population_variance():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    rng = random.SystemRandom()
    sensor_ids = rng.sample(range(10000, 2000000000), 3)
    bases = [rng.randrange(10**12, 2 * 10**12) for _ in range(3)]
    groups = {
        sensor_ids[0]: [bases[0] - 0.75, bases[0] - 0.25,
                        bases[0] + 0.25, bases[0] + 0.75],
        sensor_ids[1]: [bases[1], bases[1] + 0.5, bases[1] + 1.0],
        sensor_ids[2]: [bases[2] + 2.0] * 4,
    }

    records = [(sid, value) for sid, values in groups.items() for value in values]
    rng.shuffle(records)
    payload = b"".join(struct.pack("<id", sid, value) for sid, value in records)

    expected = []
    for sid in sorted(groups):
        values = groups[sid]
        mean = math.fsum(values) / len(values)
        variance = math.fsum((value - mean) ** 2 for value in values) / len(values)
        expected.append(f"{sid}: {variance:.4f}")

    try:
        with open(DATA_PATH, "w", encoding="ascii") as f:
            f.write(base64.b64encode(payload).decode("ascii"))
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        run_artifact()
        assert os.path.isfile(OUTPUT_PATH), "The script did not create fixed_variances.txt"
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            actual = f.read().splitlines()

        assert all(re.fullmatch(r"-?\d+: \d+\.\d{4}", line) for line in actual), (
            "Every output line must use exactly the format 'SensorID: Variance' "
            "with four decimal places."
        )
        assert actual == expected, (
            "The script failed on freshly generated little-endian <id> records, "
            "or did not compute sorted, numerically stable population variances.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        run_artifact()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
