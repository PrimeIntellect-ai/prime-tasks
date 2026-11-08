#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

PROJECT = "/home/user/stats_project"
HEADER = os.path.join(PROJECT, "stats.h")
MAKEFILE = os.path.join(PROJECT, "Makefile")
EXECUTABLE = os.path.join(PROJECT, "calc_variance")
DATASET = os.path.join(PROJECT, "dataset.txt")
RESULT = os.path.join(PROJECT, "final_result.txt")

EXPECTED_HEADER = b"""#ifndef STATS_H
#define STATS_H
double compute_mean(double *arr, int n);
#endif
"""


def expected_output(values):
    total = 0.0
    correction = 0.0
    for value in values:
        y = value - correction
        updated = total + y
        correction = (updated - total) - y
        total = updated
    mean = total / len(values)

    variance = 0.0
    for value in values:
        variance += (value - mean) * (value - mean)
    variance /= len(values)
    return f"{variance:.4f}\n"


def run_calculator(path):
    completed = subprocess.run(
        [EXECUTABLE, path],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert completed.returncode == 0, (
        f"calc_variance failed for {path} with exit code "
        f"{completed.returncode}: {completed.stderr.decode(errors='replace')}"
    )
    return completed.stdout.decode("utf-8")


def test_stats_h_recovered():
    assert os.path.isfile(HEADER), f"{HEADER} is missing. Did you recover it from git?"
    with open(HEADER, "rb") as f:
        content = f.read()
    assert content == EXPECTED_HEADER, "stats.h does not contain the recovered header contents."


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE), f"{MAKEFILE} is missing."
    with open(MAKEFILE, "r") as f:
        content = f.read()
    assert "-llegacy" not in content, "Makefile still contains '-llegacy'. You must remove it to resolve the symbol conflict."
    assert "-ladvanced" in content, "Makefile must still link against '-ladvanced'."


def test_make_builds_application():
    completed = subprocess.run(
        ["make", "-B", "calc_variance"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert completed.returncode == 0, (
        "make failed:\n"
        + completed.stdout.decode(errors="replace")
        + completed.stderr.decode(errors="replace")
    )


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing. Did you compile the application?"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."


def test_calculator_on_dataset_and_final_result():
    assert os.path.isfile(DATASET), f"{DATASET} is missing."
    with open(DATASET, "r") as f:
        values = [float(token) for token in f.read().split()]
    assert values, "dataset.txt is empty."

    expected = expected_output(values)
    actual = run_calculator(DATASET)
    assert actual == expected, f"Expected calculator output {expected!r}, but got {actual!r}."

    assert os.path.isfile(RESULT), f"{RESULT} is missing. Did you run the program and redirect the output?"
    with open(RESULT, "r") as f:
        content = f.read()
    assert content.strip() == "8.0000", f"Expected '8.0000' in {RESULT}, but got '{content.strip()}'."
    assert content == actual, "final_result.txt is not the exact standard output of calc_variance on dataset.txt."


def test_calculator_on_unseen_inputs():
    for case in range(4):
        count = 7 + secrets.randbelow(18)
        values = [float(secrets.randbelow(2001) - 1000) for _ in range(count)]
        expected = expected_output(values)
        fd, path = tempfile.mkstemp(prefix=f"variance_case_{case}_", suffix=".txt")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(" ".join(repr(value) for value in values) + "\n")
            actual = run_calculator(path)
            assert actual == expected, (
                f"Incorrect variance for verifier-generated input: expected {expected!r}, "
                f"got {actual!r}."
            )
        finally:
            os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
