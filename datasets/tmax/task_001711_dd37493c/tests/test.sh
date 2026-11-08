#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess


def test_solution_file_exists():
    """Test that the solution.txt file exists."""
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(solution_path), f"Expected solution file not found at {solution_path}"


def test_solution_content():
    """Test that the solution.txt contains the correct converged value."""
    solution_path = "/home/user/solution.txt"
    with open(solution_path, "r") as f:
        content = f.read().strip()

    assert content == "2.25", f"Expected solution to be '2.25', but got '{content}'"


def test_script_modified_correctly():
    """Test that the Go script still has the required constants but added clipping logic."""
    script_path = "/home/user/test_stability.go"
    assert os.path.isfile(script_path), f"Go script missing at {script_path}"

    with open(script_path, "r") as f:
        content = f.read()

    # Check that initial conditions were not changed
    assert "x := 4.0" in content or "x = 4.0" in content, "Initial x value was changed."
    assert "lr := 0.1" in content or "lr = 0.1" in content, "Learning rate was changed."
    assert "iterations := 1000" in content or "iterations = 1000" in content, "Iterations count was changed."

    # Retain the original clipping-presence assertion.
    has_clipping = ("5.0" in content and "-5.0" in content) or ("5" in content and "-5" in content)
    assert has_clipping, "Could not find gradient clipping logic (checking for bounds 5.0 and -5.0) in the script."


def test_script_compiles_and_runs_with_clipped_result():
    """Compile and execute the submitted artifact and verify its numerical behavior."""
    script_path = "/home/user/test_stability.go"
    binary_path = "/tmp/test_stability_submission"

    build = subprocess.run(
        ["go", "build", "-o", binary_path, script_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert build.returncode == 0, f"Go script did not compile:\n{build.stderr}"

    run = subprocess.run(
        [binary_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert run.returncode == 0, f"Compiled Go script failed:\n{run.stderr}"

    # Independently derive the expected result using the required update rule.
    expected = 4.0
    for _ in range(1000):
        grad = 4 * expected**3 - 9 * expected**2
        grad = max(-5.0, min(5.0, grad))
        expected -= 0.1 * grad

    match = re.search(
        r"Final\s+x\s*:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)",
        run.stdout,
    )
    assert match, f"Script did not print a numeric final x value. Output was: {run.stdout!r}"
    actual = float(match.group(1))
    assert math.isfinite(actual), f"Final x was not finite: {actual}"
    assert abs(actual - expected) <= 1e-6, (
        f"Executed script produced Final x={actual}, expected {expected} from gradient clipping"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
