#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest


def test_analysis_and_diffusion_result():
    script_path = "/home/user/run_analysis.sh"
    result_path = "/home/user/diffusion_result.txt"

    assert os.path.isfile(script_path), f"File {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."

    # Ensure the result being graded is produced by a fresh end-to-end run.
    if os.path.exists(result_path):
        os.remove(result_path)

    try:
        completed = subprocess.run(
            [script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("run_analysis.sh did not complete within 300 seconds.")

    assert completed.returncode == 0, (
        f"run_analysis.sh exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )

    assert os.path.isfile(result_path), f"File {result_path} does not exist. The script did not produce the expected output file."

    with open(result_path, 'r') as f:
        content = f.read().strip()

    try:
        pred_d = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {result_path} as a float. Content: '{content}'")

    truth_d = 0.015
    tolerance = 0.002

    assert abs(pred_d - truth_d) <= tolerance, (
        f"Predicted diffusion coefficient D={pred_d} is outside the acceptable "
        f"tolerance {tolerance} of the ground truth {truth_d}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
