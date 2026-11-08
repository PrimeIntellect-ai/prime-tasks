#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile

SOURCE = "/home/user/fit_model.c"
EXECUTABLE = "/home/user/fit_model"
RESULTS = "/home/user/results.txt"
FLOAT_TOKEN = r"[+-]?(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?"


def test_fit_model_c_modified():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."

    with open(SOURCE, "r") as f:
        content = f.read()

    # Keep the original source assertions.
    assert re.search(r"double\s+total_prob\s*=\s*0\.0;", content), "The accumulator 'total_prob' was not changed to 'double'."
    assert re.search(r"double\s*\*\s*p_vals\s*=\s*malloc\(N\s*\*\s*sizeof\(double\)\);", content), "The array 'p_vals' was not changed to 'double'."
    assert "float total_prob" not in content, "'float total_prob' is still present in the file."
    assert "float* p_vals" not in content, "'float* p_vals' is still present in the file."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing. Did you compile the C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXECUTABLE} is not a compiled ELF executable."


def run_model(path, n):
    completed = subprocess.run(
        [path, str(n)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
        check=True,
    )
    assert re.fullmatch(FLOAT_TOKEN + r"\n?", completed.stdout), (
        f"Running {path} with N={n} did not produce exactly one floating-point output: "
        f"{completed.stdout!r}"
    )
    return completed.stdout.strip()


def test_program_behavior_and_results():
    # Independently compile the submitted source with the command required by the task.
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "fit_model")
        subprocess.run(
            ["gcc", "-O2", SOURCE, "-o", rebuilt, "-lm"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
            check=True,
        )

        installed_outputs = []
        for n in (1000, 10000000):
            installed = run_model(EXECUTABLE, n)
            rebuilt_output = run_model(rebuilt, n)
            assert installed == rebuilt_output, (
                f"The installed executable output for N={n} does not match a fresh "
                "gcc -O2 build of fit_model.c."
            )

            value = float(installed)
            assert math.isfinite(value), f"Output for N={n} is not finite."

            # For midpoint quadrature of this parabola, normalization error is 0.5/N^2.
            expected = 0.5 / (n * n)
            tolerance = 5e-8
            assert abs(value - expected) <= tolerance, (
                f"Output for N={n} is {installed}, inconsistent with the corrected "
                f"double-precision computation (expected approximately {expected:.12g})."
            )
            installed_outputs.append(installed)

    assert os.path.isfile(RESULTS), f"Results file {RESULTS} is missing."
    with open(RESULTS, "r") as f:
        content = f.read()

    match = re.fullmatch(
        rf"({FLOAT_TOKEN})\n({FLOAT_TOKEN})\n?",
        content,
    )
    assert match is not None, f"{RESULTS} must contain exactly two floating-point lines."
    lines = [match.group(1), match.group(2)]
    assert lines == installed_outputs, (
        f"{RESULTS} does not exactly contain the executable outputs for N=1000 and "
        f"N=10000000. Expected {installed_outputs!r}, got {lines!r}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
