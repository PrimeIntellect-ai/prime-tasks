#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import math

def get_percentile(sorted_data, p):
    n = len(sorted_data)
    k = (n - 1) * (p / 100.0)
    f = int(math.floor(k))
    c = int(math.ceil(k))
    if f == c:
        return sorted_data[int(k)]
    d0 = sorted_data[f] * (c - k)
    d1 = sorted_data[c] * (k - f)
    return d0 + d1

def test_solver_executable_exists():
    executable = "/home/user/sim/solver"
    assert os.path.isfile(executable), f"Executable not found at {executable}"
    assert os.access(executable, os.X_OK), f"File {executable} is not executable"

def test_stability_ci_file():
    result_file = "/home/user/stability_ci.txt"
    assert os.path.isfile(result_file), f"Result file not found at {result_file}"

    # Compile the ground truth to ensure we have the exact same numbers
    # depending on the libc/libstdc++ version in the container.
    truth_exe = "/tmp/solver_truth"
    compile_res = subprocess.run(
        ["g++", "-std=c++11", "/home/user/sim/solver.cpp", "-o", truth_exe],
        capture_output=True
    )
    assert compile_res.returncode == 0, "Failed to compile ground truth solver.cpp"

    norms = []
    for i in range(1, 10001):
        res = subprocess.run(
            [truth_exe, "--seed", str(i)],
            capture_output=True,
            text=True
        )
        assert res.returncode == 0, f"Ground truth solver failed on seed {i}"
        norms.append(float(res.stdout.strip()))

    norms.sort()
    lower = get_percentile(norms, 2.5)
    upper = get_percentile(norms, 97.5)

    expected = f"{lower:.2f},{upper:.2f}"

    with open(result_file, "r") as f:
        content = f.read().strip()

    assert content == expected, f"Expected '{expected}' in {result_file}, but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
