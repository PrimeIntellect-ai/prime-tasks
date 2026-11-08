#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess

import numpy as np

RESULT_PATH = "/home/user/variance_results.csv"
PRIMER_PATH = "/home/user/primer.fasta"


def expected_pair(fasta_bytes):
    lines = fasta_bytes.decode("utf-8").splitlines()
    sequence = "".join(line.strip() for line in lines if not line.startswith(">")).upper()
    assert sequence, "Primer sequence is empty"

    length = len(sequence)
    gc_percent = (sequence.count("G") + sequence.count("C")) / length * 100.0

    np.random.seed(42)
    sodium = np.random.uniform(0.01, 0.1, 100000)
    tm = 81.5 + 16.6 * np.log10(sodium) + 0.41 * gc_percent - 600.0 / length
    x = np.array(tm + 1_000_000_000, dtype=np.float64)
    n = len(x)

    naive = (np.sum(x ** 2) - (np.sum(x) ** 2) / n) / n
    mean = np.sum(x) / n
    twopass = np.sum((x - mean) ** 2) / n
    return float(f"{naive:.4f}"), float(f"{twopass:.4f}")


def read_pair():
    assert os.path.exists(RESULT_PATH), f"File {RESULT_PATH} is missing. Did you save the results?"
    assert os.path.isfile(RESULT_PATH), f"Path {RESULT_PATH} is not a file."

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    assert content, "The variance_results.csv file is empty."
    assert len(content.splitlines()) == 1, "variance_results.csv must contain a single line."

    parts = content.split(",")
    assert len(parts) == 2, f"Expected 2 comma-separated values, but got {len(parts)}: '{content}'"

    try:
        pair = float(parts[0]), float(parts[1])
    except ValueError:
        assert False, f"Could not parse the results as floats. File content: '{content}'"

    assert all(math.isfinite(value) for value in pair), "Variance values must be finite."
    return pair


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        rel = os.path.relpath(root, "/home/user")
        if rel != "." and rel.count(os.sep) >= 2:
            dirs[:] = []
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            is_python = name.endswith(".py")
            if not is_python:
                try:
                    with open(path, "rb") as f:
                        is_python = b"python" in f.readline().lower()
                except OSError:
                    continue
            if is_python:
                scripts.append(path)
    return sorted(scripts)


def run_and_check(script, fasta_bytes):
    with open(PRIMER_PATH, "wb") as f:
        f.write(fasta_bytes)
    if os.path.lexists(RESULT_PATH):
        os.remove(RESULT_PATH)

    completed = subprocess.run(
        ["python3", script],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    if completed.returncode != 0:
        return False
    try:
        actual = read_pair()
        expected = expected_pair(fasta_bytes)
        return actual == expected
    except AssertionError:
        return False


def test_results_and_executable_simulation():
    # Preserve the original verifier's file and content assertions.
    original_primer = open(PRIMER_PATH, "rb").read()
    original_result = open(RESULT_PATH, "rb").read() if os.path.isfile(RESULT_PATH) else None

    var_naive, var_twopass = read_pair()

    expected_twopass = 53.4725
    assert math.isclose(var_twopass, expected_twopass, abs_tol=0.001), \
        f"Two-pass variance {var_twopass} is incorrect. Expected approximately {expected_twopass}."

    assert var_naive < 1.0 or var_naive < 0, \
        f"Naive variance {var_naive} did not exhibit the expected catastrophic cancellation. Expected ~0.0000."

    # Add the missing exact check for the required naive NumPy calculation.
    expected_default = expected_pair(original_primer)
    assert (var_naive, var_twopass) == expected_default, \
        f"Results {(var_naive, var_twopass)} do not match the required calculations {expected_default}."

    scripts = find_python_scripts()
    assert scripts, "No Python simulation script was found under /home/user."

    cases = [
        original_primer,
        b">short_gc_primer\nG\n",
        b">long_gc_primer\n" + (b"GC" * 200) + b"\n",
    ]

    winner = None
    try:
        for script in scripts:
            if all(run_and_check(script, case) for case in cases):
                winner = script
                break
        assert winner is not None, \
            "No Python script regenerated both variances using the required simulation and formulas."
    finally:
        with open(PRIMER_PATH, "wb") as f:
            f.write(original_primer)
        if winner is not None:
            assert run_and_check(winner, original_primer), \
                "The simulation script failed when restoring the original primer result."
        elif original_result is not None:
            with open(RESULT_PATH, "wb") as f:
                f.write(original_result)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
