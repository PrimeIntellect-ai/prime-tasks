#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess

SOURCE = "/home/user/solve_model.c"
EXECUTABLE = "/home/user/solve_model"
INPUT = "/home/user/input.fasta"
RESULTS = "/home/user/results.csv"
REBUILT = "/tmp/rebuilt_solve_model"

ORIGINAL_FASTA = """>seqA1
ATGCATGCATGC
>seqB2
ATGC
>seqC3
ATGCATGCATGCATGCATGCATGC
>seqD4
A
"""
ORIGINAL_EXPECTED = [
    "SequenceID,FinalY",
    "seqA1,7.18",
    "seqB2,2.39",
    "seqC3,14.37",
    "seqD4,0.60",
]


def read_results():
    assert os.path.isfile(RESULTS), f"Expected results file {RESULTS} is missing."
    with open(RESULTS, "r", encoding="utf-8") as f:
        content = f.read().strip().splitlines()
    return [line.strip() for line in content if line.strip()]


def euler_final(length):
    y = float(length)
    for _ in range(10):
        y += 0.5 * (-0.1 * y)
    return f"{y:.2f}"


def run_and_check(binary, fasta_text, expected_lines):
    with open(INPUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(fasta_text)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    completed = subprocess.run(
        [binary], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"{binary} exited with status {completed.returncode}.\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert read_results() == expected_lines, (
        f"Output from {binary} was incorrect.\n"
        f"Expected: {expected_lines}\nGot: {read_results()}"
    )


def make_dynamic_fixture():
    rng = random.SystemRandom()
    count = rng.randint(5, 8)
    lengths = rng.sample(range(3, 220), count)
    records = []
    expected = ["SequenceID,FinalY"]

    for index, length in enumerate(lengths):
        sequence_id = f"dyn{index}_{secrets.token_hex(5)}"
        sequence = "".join(rng.choice("ACGT") for _ in range(length))
        width = rng.randint(7, 31)
        wrapped = "\n".join(sequence[i:i + width] for i in range(0, length, width))
        records.append(f">{sequence_id} generated description {index}\n{wrapped}\n")
        expected.append(f"{sequence_id},{euler_final(length)}")

    return "".join(records), expected


def test_complete_solution():
    # Preserve the original verifier's existence and initial fixed-output checks.
    assert os.path.isfile(SOURCE), f"Expected C source file {SOURCE} is missing."
    assert os.path.isfile(EXECUTABLE), f"Expected executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    assert read_results() == ORIGINAL_EXPECTED, (
        f"Content of {RESULTS} does not match the expected original output.\n"
        f"Expected: {ORIGINAL_EXPECTED}\nGot: {read_results()}"
    )

    # The submitted executable must actually be a compiled binary.
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not an ELF executable."

    # Independently compile the submitted C source so both source and delivered
    # executable must implement the requested behavior.
    compiled = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", REBUILT, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compiled.returncode == 0, (
        f"The submitted C source did not compile.\n"
        f"stdout: {compiled.stdout}\nstderr: {compiled.stderr}"
    )

    try:
        # Re-run both artifacts on the original fixture rather than trusting a
        # pre-created results.csv.
        run_and_check(EXECUTABLE, ORIGINAL_FASTA, ORIGINAL_EXPECTED)
        run_and_check(REBUILT, ORIGINAL_FASTA, ORIGINAL_EXPECTED)

        # Hidden runtime-generated fixtures require general FASTA parsing, ID
        # extraction, length calculation, and ten Euler updates.
        for binary in (EXECUTABLE, REBUILT):
            fasta_text, expected = make_dynamic_fixture()
            run_and_check(binary, fasta_text, expected)
    finally:
        # Leave the task's original input and generated output in place.
        with open(INPUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(ORIGINAL_FASTA)
        try:
            subprocess.run(
                [EXECUTABLE], cwd="/home/user", stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=10
            )
        except Exception:
            pass


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
