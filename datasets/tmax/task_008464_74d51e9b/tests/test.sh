#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

SOURCE = "/home/user/det_sim.cpp"
RESULTS = "/home/user/sim_results.txt"
EXECUTABLE = "/tmp/det_sim_verifier"


def test_cpp_file_exists():
    """Check if the C++ source file exists."""
    assert os.path.isfile(SOURCE), "The file /home/user/det_sim.cpp does not exist."


def test_compile_and_run_cpp_program():
    """Compile the submitted source and require it to generate a fresh results file."""
    if os.path.lexists(EXECUTABLE):
        os.remove(EXECUTABLE)
    if os.path.lexists(RESULTS):
        os.remove(RESULTS)

    compiled = subprocess.run(
        ["/usr/bin/g++", "-O3", "-std=c++17", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compiled.returncode == 0, f"Failed to compile det_sim.cpp:\n{compiled.stderr}"
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK), \
        "Compilation did not produce an executable."

    try:
        executed = subprocess.run(
            ["/usr/sbin/runuser", "-u", "user", "--", EXECUTABLE],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        assert False, "The compiled simulation did not finish within 300 seconds."

    assert executed.returncode == 0, \
        f"The compiled simulation exited with code {executed.returncode}:\n{executed.stderr}"


def test_results_file_exists():
    """Check if the executed program created the results file."""
    assert os.path.isfile(RESULTS), "The file /home/user/sim_results.txt does not exist."


def test_results_content():
    """Check if the freshly generated results contain the correct deterministic values."""
    with open(RESULTS, "r") as f:
        content = f.read()

    expected_values = {
        "Mean": "-0.001602",
        "CI_Lower": "-0.004419",
        "CI_Upper": "0.001300",
        "Prob_Near_Singular": "0.046920"
    }

    parsed_values = {}
    for line in content.strip().split('\n'):
        if ':' in line:
            key, val = line.split(':', 1)
            parsed_values[key.strip()] = val.strip()

    for key, expected_val in expected_values.items():
        assert key in parsed_values, f"Key '{key}' missing in /home/user/sim_results.txt"
        assert parsed_values[key] == expected_val, \
            f"Expected {key} to be {expected_val}, but got {parsed_values[key]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
