#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

import h5py
import numpy as np
import pytest

N = 50


def simulate(initial, D, dt, steps):
    P = np.array(initial, dtype=np.float64, copy=True)
    for _ in range(steps):
        P_new = P.copy()
        lap = (
            P[:-2, 1:-1] + P[2:, 1:-1]
            + P[1:-1, :-2] + P[1:-1, 2:]
            - 4.0 * P[1:-1, 1:-1]
        )
        P_new[1:-1, 1:-1] += D * dt * lap
        P = P_new
    return P


def canonical_initial():
    P = np.zeros((N, N), dtype=np.float64)
    P[N // 2, N // 2] = 1.0
    return P


def expected_output():
    return simulate(canonical_initial(), 0.1, 2.5, 4)


def expected_reference():
    return simulate(canonical_initial(), 0.12, 1.0, 10)


def compute_expected_tv():
    return 0.5 * np.sum(np.abs(expected_output() - expected_reference()))


def read_p(path):
    with h5py.File(path, "r") as f:
        assert "P" in f, f"Missing dataset P in {path}"
        value = np.asarray(f["P"], dtype=np.float64)
    assert value.shape == (N, N), f"Dataset P in {path} has shape {value.shape}, expected {(N, N)}"
    assert np.all(np.isfinite(value)), f"Dataset P in {path} contains NaN or infinity"
    return value


def run_and_check(executable):
    rng = np.random.default_rng(91723)
    initial = rng.random((N, N), dtype=np.float64)
    initial /= initial.sum()
    expected = simulate(initial, 0.1, 2.5, 4)

    with tempfile.TemporaryDirectory() as tmp:
        input_path = os.path.join(tmp, "input.h5")
        output_path = os.path.join(tmp, "output.h5")
        with h5py.File(input_path, "w") as f:
            f.create_dataset("P", data=initial)

        result = subprocess.run(
            [executable, input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"{executable} failed with status {result.returncode}: {result.stderr}"
        )
        assert os.path.exists(output_path), f"{executable} did not create its output HDF5 file"
        actual = read_p(output_path)
        np.testing.assert_allclose(actual, expected, rtol=0.0, atol=1e-12)


def test_simulate_markov_c_fixed():
    c_file = "/home/user/simulate_markov.c"
    assert os.path.exists(c_file), f"Missing source file: {c_file}"
    with open(c_file, "r") as f:
        content = f.read()
    assert "2.5" in content, "The C code does not appear to contain the correct max stable dt value (2.5)."

    with tempfile.TemporaryDirectory() as tmp:
        verified_exe = os.path.join(tmp, "simulate_markov")
        result = subprocess.run(
            ["h5cc", c_file, "-o", verified_exe],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"Submitted source does not compile with h5cc: {result.stderr}"
        run_and_check(verified_exe)


def test_compiled_executable_exists():
    exe_file = "/home/user/simulate_markov"
    assert os.path.exists(exe_file), f"Missing compiled executable: {exe_file}"
    assert os.access(exe_file, os.X_OK), f"File is not executable: {exe_file}"
    run_and_check(exe_file)


def test_out_h5_exists_and_is_correct():
    out_file = "/home/user/out.h5"
    assert os.path.exists(out_file), f"Missing output file: {out_file}"
    actual = read_p(out_file)
    np.testing.assert_allclose(actual, expected_output(), rtol=0.0, atol=1e-12)


def test_provided_inputs_are_intact():
    np.testing.assert_array_equal(read_p("/home/user/init.h5"), canonical_initial())
    np.testing.assert_allclose(read_p("/home/user/ref.h5"), expected_reference(), rtol=0.0, atol=1e-12)


def test_tv_distance_result():
    result_file = "/home/user/tv_distance.txt"
    assert os.path.exists(result_file), f"Missing result file: {result_file}"

    with open(result_file, "r") as f:
        content = f.read()

    assert content.strip(), f"Result file {result_file} is empty."
    assert re.fullmatch(r"[0-9]+\.[0-9]{4}\n?", content), (
        "TV distance must be written as a number rounded to exactly 4 decimal places"
    )

    try:
        student_val = float(content.strip())
    except ValueError:
        pytest.fail(f"Could not parse a float from {result_file}. Found: '{content}'")

    expected_val = compute_expected_tv()
    expected_str = f"{expected_val:.4f}"
    assert f"{student_val:.4f}" == expected_str, (
        f"Incorrect TV distance. Expected {expected_str}, but got {student_val:.4f}"
    )

    actual_tv = 0.5 * np.sum(np.abs(read_p("/home/user/out.h5") - read_p("/home/user/ref.h5")))
    assert content.strip() == f"{actual_tv:.4f}", (
        "tv_distance.txt does not contain the TV distance computed from out.h5 and ref.h5"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
