#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import pytest

def generate_expected_data():
    k = 1.5
    c = 0.2
    dt = 0.1
    steps = 50
    x0_list = [1.0, 2.0, 3.0]

    lines = ["t,x,v,x0"]

    for x0 in x0_list:
        x = x0
        v = 0.0
        t = 0.0
        for _ in range(steps + 1):
            lines.append(f"{t:.4f},{x:.4f},{v:.4f},{x0:.1f}")

            # Forward Euler
            x_new = x + v * dt
            v_new = v + (-k * x - c * v) * dt

            x = x_new
            v = v_new
            t += dt

    return lines

def test_generate_script_exists_and_executable():
    """Verify that generate.sh exists and is executable."""
    script_path = "/home/user/pipeline/generate.sh"
    assert os.path.exists(script_path), f"File {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {script_path} is not executable."

def test_run_pipeline_script_exists_and_executable():
    """Verify that run_pipeline.sh exists and is executable."""
    script_path = "/home/user/pipeline/run_pipeline.sh"
    assert os.path.exists(script_path), f"File {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {script_path} is not executable."

def test_training_data_csv_correctness():
    """Verify that training_data.csv has the exact expected contents."""
    csv_path = "/home/user/pipeline/training_data.csv"
    assert os.path.exists(csv_path), f"File {csv_path} was not generated."
    assert os.path.isfile(csv_path), f"{csv_path} is not a file."

    with open(csv_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    expected_lines = generate_expected_data()

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {csv_path}, but found {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at line {i + 1} of {csv_path}.\n"
            f"Expected: {expected}\n"
            f"Found:    {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
