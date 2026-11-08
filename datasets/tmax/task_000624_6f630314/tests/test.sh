#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile

SOURCE = "/home/user/kmer_dist.c"
BINARY = "/home/user/kmer_dist"
DATA = "/home/user/data.fasta"
RESULT = "/home/user/result.txt"
REBUILT = "/tmp/kmer_dist_rebuilt"
BASES = "ACGT"


def expected_output(sequences):
    counts = [0] * 64
    total = 0
    mapping = {"A": 0, "C": 1, "G": 2, "T": 3}
    for sequence in sequences:
        for pos in range(len(sequence) - 2):
            idx = 0
            valid = True
            for base in sequence[pos:pos + 3]:
                if base not in mapping:
                    valid = False
                    break
                idx = (idx << 2) | mapping[base]
            if valid:
                counts[idx] += 1
                total += 1

    assert total > 0
    probabilities = [count / total for count in counts]
    probabilities = [p + 1e-6 for p in probabilities]
    normalization = sum(probabilities)
    probabilities = [p / normalization for p in probabilities]
    q = 1.0 / 64.0
    kl = sum(p * math.log2(p / q) for p in probabilities)
    return f"KL Divergence: {kl:.4f}\n"


def read_fasta(path):
    sequences = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith(">"):
                sequences.append(line)
    return sequences


def write_fasta(sequences):
    fd, path = tempfile.mkstemp(prefix="kmer_test_", suffix=".fasta")
    with os.fdopen(fd, "w") as f:
        for i, sequence in enumerate(sequences):
            f.write(f">random_{i}\n{sequence}\n")
    return path


def run_program(binary, fasta, threads=8):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(threads)
    completed = subprocess.run(
        [binary, fasta],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"{binary} failed with status {completed.returncode}: {completed.stderr}"
    )
    assert re.fullmatch(r"KL Divergence: -?\d+\.\d{4}\n", completed.stdout), (
        f"Incorrect output format from {binary}: {completed.stdout!r}"
    )
    return completed.stdout


def random_sequence(length):
    return "".join(BASES[secrets.randbelow(4)] for _ in range(length))


def test_result_txt_exists_and_correct():
    assert os.path.isfile(RESULT), f"File {RESULT} is missing. Did you run the program and redirect output?"
    with open(RESULT, "r") as f:
        content = f.read().strip()

    expected = "KL Divergence: 2.0191"
    assert expected in content, f"Expected output '{expected}' not found in {RESULT}. Found: '{content}'"
    assert content == expected, f"{RESULT} must contain exactly one correctly formatted result."

    derived = expected_output(read_fasta(DATA)).strip()
    assert content == derived, f"Saved result does not match the calculation for {DATA}."
    assert run_program(BINARY, DATA).strip() == content, (
        "The installed executable does not reproduce result.txt on the provided dataset."
    )


def test_executable_exists():
    assert os.path.isfile(BINARY), f"Executable {BINARY} is missing. Did you compile the C program?"
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."
    linked = subprocess.run(["ldd", BINARY], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert "libgomp" in linked.stdout, "The executable is not linked with the OpenMP runtime."


def test_c_code_contains_openmp_fixes():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()

    assert "#pragma omp parallel" in content or "_Pragma" in content, "OpenMP parallel directive is missing from the code."

    has_atomic = "atomic" in content
    has_critical = "critical" in content
    has_reduction = "reduction" in content
    has_locks = "omp_set_lock" in content
    assert any([has_atomic, has_critical, has_reduction, has_locks]), "No OpenMP synchronization (atomic, critical, reduction, or locks) found to fix the race condition."


def test_c_code_contains_smoothing():
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "1e-6" in content or "0.000001" in content, "Additive smoothing of 1e-6 is not found in the code."


def test_source_builds_and_both_binaries_compute_dynamic_cases():
    compiled = subprocess.run(
        ["gcc", "-O2", "-fopenmp", SOURCE, "-lm", "-o", REBUILT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f"The submitted C source does not compile: {compiled.stderr}"

    sparse = [random_sequence(11 + secrets.randbelow(35)) for _ in range(19)]
    dense = [random_sequence(800 + secrets.randbelow(80)) for _ in range(320)]

    for sequences, repetitions in ((sparse, 1), (dense, 4)):
        path = write_fasta(sequences)
        try:
            expected = expected_output(sequences)
            for binary in (BINARY, REBUILT):
                for _ in range(repetitions):
                    actual = run_program(binary, path, threads=8)
                    assert actual == expected, (
                        f"{binary} computed {actual.strip()!r}; expected {expected.strip()!r}"
                    )
        finally:
            os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
