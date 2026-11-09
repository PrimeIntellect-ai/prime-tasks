#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import pytest

FASTA_PATH = "/home/user/dna.fasta"
RESULT_PATH = "/home/user/integral_result.txt"
SOURCE_PATH = "/home/user/process.c"
ORIGINAL_SEQUENCE = "ATGCGTACGTAGCT"


def compute_expected_integral(fasta_path):
    if not os.path.exists(fasta_path):
        return None

    with open(fasta_path, 'r') as f:
        lines = f.readlines()

    seq = ""
    for line in lines:
        line = line.strip()
        if not line.startswith(">"):
            seq += line

    mapping = {'A': 1.0, 'C': 2.0, 'G': 3.0, 'T': 4.0}
    X = [mapping[c] for c in seq if c in mapping]
    N = len(X)
    if N == 0:
        return 0.0

    Y = [0.0] * N
    for i in range(N):
        left = X[i-1] if i - 1 >= 0 else 0.0
        right = X[i+1] if i + 1 < N else 0.0
        Y[i] = left + 2.0 * X[i] + right

    if N == 1:
        return Y[0]

    integral = (Y[0] / 2.0) + sum(Y[1:N-1]) + (Y[N-1] / 2.0)
    return integral


def parsed_sequence(fasta_path):
    with open(fasta_path, 'r') as f:
        return ''.join(line.strip() for line in f if not line.startswith('>'))


def test_process_c_exists_and_uses_openmp():
    c_file = SOURCE_PATH
    assert os.path.isfile(c_file), f"C source file {c_file} is missing."

    with open(c_file, 'r') as f:
        content = f.read()

    assert "omp.h" in content or "omp " in content, f"The file {c_file} does not appear to use OpenMP."
    assert re.search(r"#\s*pragma\s+omp\s+(?:parallel\s+for|for)\b", content), \
        "The convolution loop does not appear to have an OpenMP work-sharing directive."


def test_original_fasta_was_not_replaced():
    assert os.path.isfile(FASTA_PATH), f"Input FASTA file {FASTA_PATH} is missing."
    assert parsed_sequence(FASTA_PATH) == ORIGINAL_SEQUENCE, \
        "The supplied DNA sequence was modified."


def test_integral_result_correct():
    result_file = RESULT_PATH
    fasta_file = FASTA_PATH

    assert os.path.isfile(result_file), f"Result file {result_file} is missing."

    expected_integral = compute_expected_integral(fasta_file)
    assert expected_integral is not None, f"Input FASTA file {fasta_file} is missing."

    expected_str = f"{expected_integral:.1f}"

    with open(result_file, 'r') as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, f"Expected integral result '{expected_str}', but got '{actual_str}' in {result_file}."


def test_compiles_and_runs_on_independent_inputs():
    with open(FASTA_PATH, 'rb') as f:
        original_fasta = f.read()
    original_result = None
    if os.path.exists(RESULT_PATH):
        with open(RESULT_PATH, 'rb') as f:
            original_result = f.read()

    rng = random.SystemRandom()
    random_sequence = ''.join(rng.choice('ACGT') for _ in range(257))
    cases = [
        ">short\nAT\n",
        ">multi_line\nGATTACA\nCGTAGC\n",
        ">randomized\n" + '\n'.join(random_sequence[i:i+37] for i in range(0, len(random_sequence), 37)) + "\n",
    ]

    try:
        with tempfile.TemporaryDirectory() as td:
            executable = os.path.join(td, "process")
            compiled = subprocess.run(
                ["gcc", "-O2", "-fopenmp", SOURCE_PATH, "-o", executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert compiled.returncode == 0, f"process.c failed to compile with OpenMP:\n{compiled.stderr}"

            for fasta in cases:
                with open(FASTA_PATH, 'w') as f:
                    f.write(fasta)
                if os.path.exists(RESULT_PATH):
                    os.remove(RESULT_PATH)

                expected = f"{compute_expected_integral(FASTA_PATH):.1f}"
                env = os.environ.copy()
                env["OMP_NUM_THREADS"] = "4"
                ran = subprocess.run(
                    [executable],
                    cwd="/home/user",
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                )
                assert ran.returncode == 0, f"Compiled program exited with status {ran.returncode}:\n{ran.stderr}"
                assert os.path.isfile(RESULT_PATH), "Compiled program did not create integral_result.txt."
                with open(RESULT_PATH, 'r') as f:
                    actual = f.read().strip()
                assert re.fullmatch(r"-?\d+\.\d", actual), \
                    f"Result '{actual}' is not formatted to exactly one decimal place."
                assert actual == expected, f"For test FASTA, expected '{expected}' but program wrote '{actual}'."
    finally:
        with open(FASTA_PATH, 'wb') as f:
            f.write(original_fasta)
        if original_result is None:
            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)
        else:
            with open(RESULT_PATH, 'wb') as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
