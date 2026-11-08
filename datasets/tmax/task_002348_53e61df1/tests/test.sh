#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
from pathlib import Path

import pytest

HOME = Path("/home/user")
SOURCE = HOME / "pipeline.c"
BINARY = Path("/tmp/verified_pipeline")
PREDICTIONS = HOME / "predictions.csv"

ORIGINAL = {
    "sensor1": [(1, 10.0, 20.0), (2, 15.0, 25.0), (3, 12.0, 22.0)],
    "sensor2": [(3, 5.0, 2.0), (1, 8.0, 4.0), (2, 6.0, 3.0)],
    "pca": [(0.5, 0.5), (-0.5, 0.5), (0.5, -0.5), (-0.5, -0.5)],
    "model": [1.0, -1.0],
}

HIDDEN_CASES = [
    {
        "sensor1": [(42, 2.0, 4.0), (7, 1.0, 3.0), (19, -2.0, 5.0)],
        "sensor2": [(19, 6.0, -1.0), (42, 8.0, 2.0), (7, 4.0, 0.0)],
        "pca": [(1.0, 0.0), (0.0, 1.0), (1.0, 1.0), (-1.0, 1.0)],
        "model": [2.0, -1.0],
    },
    {
        "sensor1": [(80, 4.0, -1.0), (5, 2.0, 1.0), (13, -2.0, 3.0)],
        "sensor2": [(13, 4.0, -1.0), (5, 9.0, 2.0), (80, 0.0, 3.0)],
        "pca": [(0.25, -0.5), (1.0, 0.5), (-0.5, 0.25), (0.75, -1.0)],
        "model": [2.0, 4.0],
    },
]


def write_case(case):
    with open(HOME / "sensor1.csv", "w", newline="") as f:
        f.write("id,f1,f2\n")
        for record_id, f1, f2 in case["sensor1"]:
            f.write(f"{record_id},{f1},{f2}\n")

    with open(HOME / "sensor2.csv", "w", newline="") as f:
        f.write("id,f3,f4\n")
        for record_id, f3, f4 in case["sensor2"]:
            f.write(f"{record_id},{f3},{f4}\n")

    with open(HOME / "pca_weights.txt", "w") as f:
        for left, right in case["pca"]:
            f.write(f"{left} {right}\n")

    with open(HOME / "model_weights.txt", "w") as f:
        for weight in case["model"]:
            f.write(f"{weight}\n")


def run_pipeline(case):
    write_case(case)
    if PREDICTIONS.exists():
        PREDICTIONS.unlink()
    subprocess.run([str(BINARY)], cwd=str(HOME), check=True, timeout=5)
    assert PREDICTIONS.exists(), f"Output file not found: {PREDICTIONS}. Did the compiled C program create it?"
    with open(PREDICTIONS, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def derive_expected(case):
    sensor1 = {record_id: (f1, f2) for record_id, f1, f2 in case["sensor1"]}
    sensor2 = {record_id: (f3, f4) for record_id, f3, f4 in case["sensor2"]}
    assert sensor1.keys() == sensor2.keys()

    lines = ["id,score"]
    for record_id in sorted(sensor1):
        features = sensor1[record_id] + sensor2[record_id]
        reduced0 = sum(features[i] * case["pca"][i][0] for i in range(4))
        reduced1 = sum(features[i] * case["pca"][i][1] for i in range(4))
        score = reduced0 * case["model"][0] + reduced1 * case["model"][1]
        lines.append(f"{record_id},{score:.1f}")
    return lines


@pytest.fixture(scope="session")
def compiled_pipeline():
    subprocess.run(
        ["gcc", "-std=c11", "-O2", "-o", str(BINARY), str(SOURCE)],
        check=True,
        timeout=15,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)
    return BINARY


def test_pipeline_c_exists():
    """Verify that the user created the C source file."""
    filepath = "/home/user/pipeline.c"
    assert os.path.exists(filepath), f"The C source file {filepath} is missing. You must write your solution in C."
    assert os.path.isfile(filepath), f"The C source path {filepath} is not a file."


def test_predictions_csv_correct(compiled_pipeline):
    """Verify the original inputs produce the required exact output."""
    actual_lines = run_pipeline(ORIGINAL)

    expected_output = [
        "id,score",
        "1,-12.0",
        "2,-19.0",
        "3,-17.0",
    ]

    assert len(actual_lines) > 0, f"The file {PREDICTIONS} is empty."
    assert actual_lines[0] == expected_output[0], f"Incorrect header in {PREDICTIONS}. Expected 'id,score', got '{actual_lines[0]}'."
    assert len(actual_lines) == len(expected_output), f"Incorrect number of rows in {PREDICTIONS}. Expected {len(expected_output)}, got {len(actual_lines)}."

    for i in range(1, len(expected_output)):
        assert actual_lines[i] == expected_output[i], (
            f"Mismatch at row {i}. Expected '{expected_output[i]}', got '{actual_lines[i]}'. "
            "Check your data joining, matrix multiplication, or sorting logic."
        )


def test_compiled_pipeline_handles_changed_inputs(compiled_pipeline):
    """Exercise joining and inference with reordered, changed data and weights."""
    try:
        for case in HIDDEN_CASES:
            actual_lines = run_pipeline(case)
            expected_lines = derive_expected(case)
            assert actual_lines == expected_lines, (
                f"Compiled pipeline output was incorrect for changed inputs. "
                f"Expected {expected_lines}, got {actual_lines}."
            )
    finally:
        # Leave the requested output corresponding to the task's original files.
        run_pipeline(ORIGINAL)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
