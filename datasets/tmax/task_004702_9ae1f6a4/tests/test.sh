#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import h5py
import numpy as np

COMPUTE = "/home/user/compute_deriv.sh"
PIPELINE = "/home/user/test_pipeline.sh"


def expected_value(times, temperatures):
    derivatives = [
        abs((temperatures[i + 1] - temperatures[i]) / (times[i + 1] - times[i]))
        for i in range(len(times) - 1)
    ]
    return f"{max(derivatives):.4f}"


def run_compute(path, expected):
    result = subprocess.run(
        [COMPUTE, path], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"compute_deriv.sh failed for {path} with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    actual = result.stdout.strip()
    assert re.fullmatch(r"[0-9]+\.[0-9]{4}", actual), (
        f"Expected one non-negative number with exactly four decimal places, got {result.stdout!r}"
    )
    assert actual == expected, f"Expected {expected}, got {actual} for {path}"


def test_compute_deriv_sh():
    assert os.path.exists(COMPUTE), f"Missing script: {COMPUTE}"
    assert os.path.isfile(COMPUTE), f"Not a file: {COMPUTE}"
    assert os.access(COMPUTE, os.X_OK), f"Script is not executable: {COMPUTE}"

    with open(COMPUTE, "r", errors="replace") as f:
        source = f.read()
    assert source.startswith("#!") and "bash" in source.splitlines()[0], (
        "compute_deriv.sh must be a Bash script"
    )
    assert re.search(r"\b(?:awk|gawk|bc)\b", source), (
        "Numerical differentiation/reduction must use Bash/standard UNIX numerical utilities"
    )


def test_test_pipeline_sh():
    assert os.path.exists(PIPELINE), f"Missing script: {PIPELINE}"
    assert os.path.isfile(PIPELINE), f"Not a file: {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK), f"Script is not executable: {PIPELINE}"

    result = subprocess.run(
        [PIPELINE], cwd="/home/user", capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"test_pipeline.sh failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert "PASS" in result.stdout, f"test_pipeline.sh did not print PASS: {result.stdout!r}"


def test_sim_max_deriv_txt():
    output_path = "/home/user/sim_max_deriv.txt"
    assert os.path.exists(output_path), f"Missing output file: {output_path}"

    with h5py.File("/home/user/sim_data.h5", "r") as f:
        times = np.asarray(f["time"][:], dtype=float)
        temperatures = np.asarray(f["T"][:], dtype=float)
    expected = expected_value(times, temperatures)

    with open(output_path, "r") as f:
        actual = f.read().strip()
    assert actual == expected, (
        f"Output in {output_path} does not match expected value. "
        f"Expected '{expected}', got '{actual}'."
    )


def test_compute_deriv_on_unseen_inputs():
    nonce = secrets.randbelow(1_000_000) / 1_000_000.0
    cases = [
        (
            [0.0, 0.17, 0.91, 1.4, 3.25, 4.8],
            [2.0 + nonce, -1.0, 4.5, 4.0, -8.25, -7.0],
        ),
        (
            [10.0, 10.03, 10.7, 12.2, 15.9, 21.0, 21.2],
            [-3.0, -2.99, -9.0 - nonce, 5.0, 5.25, -30.0, -28.0],
        ),
        (
            [0.0, 0.5, 2.0, 2.125, 7.0],
            [100.0, 99.0, 102.0, 98.0 - nonce, 101.0],
        ),
    ]

    with tempfile.TemporaryDirectory() as directory:
        for index, (times, temperatures) in enumerate(cases):
            path = os.path.join(directory, f"unseen_{index}_{secrets.token_hex(8)}.h5")
            with h5py.File(path, "w") as f:
                f.create_dataset("time", data=np.asarray(times, dtype=float))
                f.create_dataset("T", data=np.asarray(temperatures, dtype=float))
            run_compute(path, expected_value(times, temperatures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
