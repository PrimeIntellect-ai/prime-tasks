#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

import pytest

SCRIPT = "/home/user/analyze_squiggles.sh"
RAW = "/home/user/raw_signal.tsv"
OUTPUTS = [
    "/home/user/iterations.txt",
    "/home/user/final_energy.txt",
    "/home/user/smoothed.tsv",
]


def compute_expected_results(signal):
    S = list(signal)
    N = len(S)
    iterations = 0

    while True:
        iterations += 1
        S_new = [0.0] * N
        S_new[0] = S[0]
        S_new[N - 1] = S[N - 1]

        max_change = 0.0
        for i in range(1, N - 1):
            S_new[i] = 0.5 * S[i] + 0.25 * S[i - 1] + 0.25 * S[i + 1]
            change = abs(S_new[i] - S[i])
            if change > max_change:
                max_change = change

        S = S_new
        if max_change < 0.001:
            break

    return iterations, sum(x ** 2 for x in S), S


def remove_outputs():
    for path in OUTPUTS:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def run_script():
    remove_outputs()
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def validate_outputs(signal):
    expected_iterations, expected_energy, expected_signal = compute_expected_results(signal)

    iterations_path = "/home/user/iterations.txt"
    assert os.path.exists(iterations_path), f"Output file {iterations_path} does not exist."
    with open(iterations_path, "r") as f:
        content = f.read().strip()
    assert content == str(expected_iterations), (
        f"Expected {expected_iterations} iterations, but got {content} in {iterations_path}."
    )

    energy_path = "/home/user/final_energy.txt"
    assert os.path.exists(energy_path), f"Output file {energy_path} does not exist."
    expected_energy_str = f"{expected_energy:.4f}"
    with open(energy_path, "r") as f:
        content = f.read().strip()
    assert content == expected_energy_str, (
        f"Expected energy {expected_energy_str}, but got {content} in {energy_path}."
    )

    smoothed_path = "/home/user/smoothed.tsv"
    assert os.path.exists(smoothed_path), f"Output file {smoothed_path} does not exist."
    with open(smoothed_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_signal), (
        f"Expected {len(expected_signal)} lines in {smoothed_path}, but got {len(lines)}."
    )

    for i, (actual, expected) in enumerate(zip(lines, expected_signal)):
        expected_str = f"{expected:.6f}"
        try:
            actual_float = float(actual)
        except ValueError:
            pytest.fail(f"Line {i + 1} in {smoothed_path} is not a valid float: '{actual}'")
        assert math.isclose(actual_float, float(expected_str), abs_tol=1e-5), (
            f"Line {i + 1} mismatch: expected {expected_str}, got {actual}."
        )


def write_signal(signal):
    with open(RAW, "w") as f:
        for value in signal:
            f.write(f"{value:.6f}\n")


def test_script_and_generated_results():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    with open(SCRIPT, "r", errors="replace") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.match(
        r"^#!\s*(?:/usr/bin/env\s+(?:-\S+\s+)*bash|/(?:usr/)?bin/bash)(?:\s|$)",
        first_line,
    ), f"{SCRIPT} must be a Bash script with a Bash shebang."

    syntax = subprocess.run(
        ["/bin/bash", "-n", SCRIPT],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert syntax.returncode == 0, f"Bash syntax check failed:\n{syntax.stderr}"

    noncomment_source = "\n".join(
        line.split("#", 1)[0] for line in source.splitlines()
    )
    assert not re.search(
        r"\b(?:python(?:\d+(?:\.\d+)*)?|perl|ruby|node(?:js)?)\b",
        noncomment_source,
        flags=re.IGNORECASE,
    ), "The smoothing implementation must be primarily Bash, not delegated to another general-purpose language."

    assert os.path.exists(RAW), f"Input file {RAW} is missing."
    with open(RAW, "rb") as f:
        original_raw = f.read()
    original_signal = [
        float(line.strip()) for line in original_raw.decode().splitlines() if line.strip()
    ]

    try:
        # Regenerate the required outputs by actually executing the submitted artifact.
        run_script()
        validate_outputs(original_signal)

        # Exercise the same script on an unpredictable signal so fixed, copied, or
        # separately hardcoded outputs cannot satisfy the verifier.
        rng = random.SystemRandom()
        dynamic_signal = [
            float(f"{rng.uniform(-2.5, 2.5):.6f}")
            for _ in range(rng.randint(8, 13))
        ]
        write_signal(dynamic_signal)
        run_script()
        validate_outputs(dynamic_signal)
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)
        # Leave the requested files corresponding to the provided input.
        run_script()


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
