#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess
import pytest

SOURCE = "/home/user/simulate.c"
EXECUTABLE = "/tmp/submission_simulate"
LOG_PATH = "/home/user/convergence_log.csv"
DIFF_PATH = "/home/user/max_diff.txt"
REFERENCE_PATH = "/home/user/reference.csv"


def get_expected_results():
    def simulate(N):
        state = 42

        def my_drand():
            nonlocal state
            state = (state * 1103515245 + 12345) % 2147483648
            return state / 2147483648.0

        counts = [0] * 5
        pos = 0
        for _ in range(N):
            r = my_drand()
            if r < 0.7:
                pos = (pos + 1) % 5
            counts[pos] += 1

        freqs = [c / N for c in counts]
        l2_error = math.sqrt(sum((f - 0.2) ** 2 for f in freqs))
        return freqs, l2_error

    results = {}
    for N in [1000, 10000, 100000, 1000000]:
        results[N] = simulate(N)
    return results


def remove_outputs():
    for path in (LOG_PATH, DIFF_PATH):
        if os.path.lexists(path):
            os.unlink(path)


def run_submission():
    result = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Compiled simulation exited with status {result.returncode}. "
        f"stdout: {result.stdout!r} stderr: {result.stderr!r}"
    )


def test_simulate_c_exists():
    assert os.path.exists(SOURCE), f"The file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"The path {SOURCE} is not a file."


def test_simulate_c_compiles_runs_and_reads_reference():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", EXECUTABLE, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE}. stdout: {compile_result.stdout!r} "
        f"stderr: {compile_result.stderr!r}"
    )
    assert os.path.isfile(EXECUTABLE), "gcc did not produce the simulation executable."

    with open(REFERENCE_PATH, "rb") as f:
        original_reference = f.read()

    alternate_ref = [0.111111, 0.222222, 0.333333, 0.444444, 0.555555]
    alternate_csv = "Node,Frequency\n" + "".join(
        f"{i},{value:.6f}\n" for i, value in enumerate(alternate_ref)
    )

    try:
        with open(REFERENCE_PATH, "w") as f:
            f.write(alternate_csv)

        remove_outputs()
        run_submission()

        assert os.path.isfile(LOG_PATH), f"Running {EXECUTABLE} did not create {LOG_PATH}."
        assert os.path.isfile(DIFF_PATH), f"Running {EXECUTABLE} did not create {DIFF_PATH}."

        with open(DIFF_PATH, "r") as f:
            content = f.read().strip()
        try:
            actual = float(content)
        except ValueError:
            pytest.fail(f"Could not parse float from {DIFF_PATH}. Content: {content!r}.")

        freqs = get_expected_results()[1000000][0]
        expected = max(abs(f - r) for f, r in zip(freqs, alternate_ref))
        assert math.isclose(actual, expected, abs_tol=1e-5), (
            "The compiled program did not calculate max_diff from the supplied "
            f"reference.csv. Expected approximately {expected:.6f}, got {actual}."
        )
    finally:
        with open(REFERENCE_PATH, "wb") as f:
            f.write(original_reference)
        remove_outputs()
        if os.path.isfile(EXECUTABLE):
            run_submission()


def test_convergence_log():
    assert os.path.exists(LOG_PATH), f"The file {LOG_PATH} is missing."

    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 lines (1 header + 4 data rows) in {LOG_PATH}, got {len(lines)}."
    assert lines[0] == "N,L2_error", f"Incorrect header in {LOG_PATH}. Expected 'N,L2_error', got '{lines[0]}'."

    expected_results = get_expected_results()
    parsed_Ns = set()
    for line in lines[1:]:
        parts = line.split(",")
        assert len(parts) == 2, f"Invalid line format in {LOG_PATH}: '{line}'. Expected 'N,L2_error'."
        try:
            N = int(parts[0])
            l2_error = float(parts[1])
        except ValueError:
            pytest.fail(f"Could not parse integers/floats from line: '{line}'.")

        assert N in expected_results, f"Unexpected N value in {LOG_PATH}: {N}. Expected one of {list(expected_results.keys())}."
        parsed_Ns.add(N)

        expected_l2 = expected_results[N][1]
        assert math.isclose(l2_error, expected_l2, abs_tol=1e-5), (
            f"For N={N}, expected L2 error approximately {expected_l2:.6f}, got {l2_error}."
        )

    assert parsed_Ns == set(expected_results.keys()), f"Missing N values in {LOG_PATH}. Expected {set(expected_results.keys())}, got {parsed_Ns}."


def test_max_diff():
    assert os.path.exists(DIFF_PATH), f"The file {DIFF_PATH} is missing."

    with open(DIFF_PATH, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse float from {DIFF_PATH}. Content: '{content}'.")

    expected_results = get_expected_results()
    freqs = expected_results[1000000][0]
    ref = [0.201, 0.198, 0.205, 0.196, 0.200]
    max_diff = max(abs(f - r) for f, r in zip(freqs, ref))

    assert math.isclose(val, max_diff, abs_tol=1e-5), (
        f"Incorrect max difference in {DIFF_PATH}. Expected approximately {max_diff:.6f}, got {val}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
