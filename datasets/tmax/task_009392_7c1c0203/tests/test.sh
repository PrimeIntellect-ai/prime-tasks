#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import runpy
import subprocess
import sys
import types
import pytest

PROFILE_PATH = "/home/user/profile_mc.py"
RESULTS_PATH = "/home/user/mc_results.csv"
VERIFY_PATH = "/home/user/verify.sh"


def test_profile_mc_exists():
    """Check if the Python profiling script was created."""
    assert os.path.exists(PROFILE_PATH), f"File {PROFILE_PATH} is missing."
    assert os.path.isfile(PROFILE_PATH), f"Path {PROFILE_PATH} is not a file."


def test_profile_mc_instrumented_behavior():
    """Execute the profiler with instrumented dependencies to prove it does the requested work."""
    events = []
    sample_sizes = [1000, 10000, 100000, 1000000]
    estimates = {
        1000: 3.0,
        10000: 3.1,
        100000: 3.2,
        1000000: 3.3,
    }
    clock_values = [100.0, 100.125, 200.0, 200.25, 300.0, 300.5, 400.0, 401.0]

    fake_random = types.ModuleType("random")
    def fake_seed(value):
        events.append(("seed", value))
    fake_random.seed = fake_seed

    fake_time = types.ModuleType("time")
    remaining_clock_values = list(clock_values)
    def fake_time_call():
        events.append(("time",))
        assert remaining_clock_values, "profile_mc.py called time.time() too many times"
        return remaining_clock_values.pop(0)
    fake_time.time = fake_time_call

    fake_mc_pi = types.ModuleType("mc_pi")
    def fake_estimate_pi(n):
        events.append(("estimate", n))
        assert n in estimates, f"Unexpected sample size passed to estimate_pi: {n}"
        return estimates[n]
    fake_mc_pi.estimate_pi = fake_estimate_pi

    old_modules = {name: sys.modules.get(name) for name in ("random", "time", "mc_pi")}
    old_results = None
    if os.path.exists(RESULTS_PATH):
        with open(RESULTS_PATH, "rb") as f:
            old_results = f.read()

    try:
        sys.modules["random"] = fake_random
        sys.modules["time"] = fake_time
        sys.modules["mc_pi"] = fake_mc_pi
        runpy.run_path(PROFILE_PATH, run_name="__main__")

        expected_events = [("seed", 42)]
        for n in sample_sizes:
            expected_events.extend([("time",), ("estimate", n), ("time",)])
        assert events == expected_events, (
            "profile_mc.py must seed once with 42 before profiling, then call time.time(), "
            "estimate_pi(N), and time.time() for each required N"
        )
        assert not remaining_clock_values, "profile_mc.py did not perform both timing calls for every N"

        with open(RESULTS_PATH, newline="") as f:
            rows = list(csv.reader(f))
        assert len(rows) == 4
        expected_times = [0.125, 0.25, 0.5, 1.0]
        for i, row in enumerate(rows):
            assert len(row) == 3
            assert int(row[0]) == sample_sizes[i]
            assert float(row[1]) == pytest.approx(expected_times[i])
            assert float(row[2]) == pytest.approx(abs(estimates[sample_sizes[i]] - math.pi))
    finally:
        for name, old_value in old_modules.items():
            if old_value is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = old_value
        if old_results is None:
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
        else:
            with open(RESULTS_PATH, "wb") as f:
                f.write(old_results)


def test_execute_profile_mc():
    """Actually run the submitted profiler to regenerate the required CSV."""
    result = subprocess.run(
        [sys.executable, PROFILE_PATH], capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, (
        f"{PROFILE_PATH} exited with status {result.returncode}. stderr: {result.stderr}"
    )


def test_mc_results_csv():
    """Check the generated CSV file for correct lines and deterministic output."""
    assert os.path.exists(RESULTS_PATH), f"File {RESULTS_PATH} is missing. Did you run your Python script?"

    with open(RESULTS_PATH, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 4, f"Expected exactly 4 lines in {RESULTS_PATH}, but found {len(rows)}."

    expected_Ns = [1000, 10000, 100000, 1000000]
    expected_errors = [
        0.013592653589793012,
        0.007607346410206803,
        0.005192653589792879,
        0.0007766535897929427
    ]

    for i, row in enumerate(rows):
        assert len(row) == 3, f"Row {i+1} does not have exactly 3 columns: {row}"

        n_val = int(row[0])
        assert n_val == expected_Ns[i], f"Row {i+1} expected N={expected_Ns[i]}, got N={n_val}"

        try:
            float(row[1])
        except ValueError:
            pytest.fail(f"Execution time in row {i+1} is not a valid float: {row[1]}")

        err_val = float(row[2])
        assert abs(err_val - expected_errors[i]) < 1e-5, \
            f"Row {i+1} expected absolute error ~{expected_errors[i]}, got {err_val}. Check if random.seed(42) was called exactly once before the loop."


def test_verify_sh_exists_and_executable():
    """Check if verify.sh exists and is executable."""
    assert os.path.exists(VERIFY_PATH), f"File {VERIFY_PATH} is missing."
    assert os.access(VERIFY_PATH, os.X_OK), f"File {VERIFY_PATH} is not executable."


def test_verify_sh_execution():
    """Check the behavior of verify.sh on the generated results."""
    result = subprocess.run([VERIFY_PATH], capture_output=True, text=True)

    assert result.returncode == 0, f"{VERIFY_PATH} exited with status code {result.returncode}, expected 0."
    assert result.stdout.strip() == "Convergence OK", f"Expected output 'Convergence OK', got '{result.stdout.strip()}'."


def test_verify_sh_reads_and_compares_csv():
    """Exercise both branches using verifier-generated CSV inputs."""
    with open(RESULTS_PATH, "rb") as f:
        original_results = f.read()

    try:
        cases = [
            (
                "1000,0.01,0.5\n10000,0.02,9.0\n100000,0.03,8.0\n1000000,0.04,0.25\n",
                0,
                "Convergence OK",
            ),
            (
                "1000,0.01,0.125\n10000,0.02,0.0\n100000,0.03,0.0\n1000000,0.04,0.125\n",
                1,
                "Convergence FAIL",
            ),
            (
                "1000,0.01,0.2\n10000,0.02,0.0\n100000,0.03,0.0\n1000000,0.04,0.7\n",
                1,
                "Convergence FAIL",
            ),
        ]
        for contents, expected_status, expected_output in cases:
            with open(RESULTS_PATH, "w") as f:
                f.write(contents)
            result = subprocess.run([VERIFY_PATH], capture_output=True, text=True)
            assert result.returncode == expected_status
            assert result.stdout.strip() == expected_output
    finally:
        with open(RESULTS_PATH, "wb") as f:
            f.write(original_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
