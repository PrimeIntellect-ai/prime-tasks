#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

CPP_PATH = "/home/user/analyze_gc.cpp"
FASTA_PATH = "/home/user/sequences.fasta"
STATS_PATH = "/home/user/stats.txt"
EXE_PATH = "/tmp/analyze_gc_verifier"


def compute_expected_stats(fasta_path):
    if not os.path.exists(fasta_path):
        return None

    with open(fasta_path, 'r') as f:
        lines = f.read().strip().split('\n')

    seqs = []
    current_seq = []
    for line in lines:
        if line.startswith('>'):
            if current_seq:
                seqs.append("".join(current_seq))
                current_seq = []
        else:
            current_seq.append(line.strip())
    if current_seq:
        seqs.append("".join(current_seq))

    ratios = []
    for seq in seqs:
        if not seq:
            continue
        gc = sum(1 for c in seq if c in ('G', 'C', 'g', 'c'))
        ratios.append(gc / len(seq))

    ratios.sort()
    N = len(ratios)

    if N < 2:
        return 0, 0, 0

    dx = 1.0 / (N - 1)
    integral = dx * ((ratios[0] + ratios[-1]) / 2.0 + sum(ratios[1:-1]))
    mean = sum(ratios) / N
    variance = sum((r - mean) ** 2 for r in ratios) / N
    std_dev = math.sqrt(variance)
    z_stat = (mean - 0.5) / (std_dev / math.sqrt(N)) if std_dev > 0 else 0.0
    return integral, mean, z_stat


def test_stats_txt_exists_and_correct():
    assert os.path.isfile(STATS_PATH), (
        f"File {STATS_PATH} is missing. The C++ program must generate it."
    )

    integral, mean, z_stat = compute_expected_stats(FASTA_PATH)
    expected_content = (
        f"Integral: {integral:.4f}\n"
        f"Mean: {mean:.4f}\n"
        f"Z-stat: {z_stat:.4f}"
    )

    with open(STATS_PATH, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Contents of {STATS_PATH} do not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )


def test_cpp_file_exists():
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} is missing."


def test_cpp_compiles():
    if os.path.exists(EXE_PATH):
        os.remove(EXE_PATH)
    result = subprocess.run(
        ["g++", "-std=c++11", "-O2", CPP_PATH, "-o", EXE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"C++ source did not compile:\n{result.stderr}"
    assert os.path.isfile(EXE_PATH) and os.access(EXE_PATH, os.X_OK)


def test_compiled_program_on_derived_inputs():
    with open(FASTA_PATH, "rb") as f:
        original_fasta = f.read()
    original_stats = None
    if os.path.exists(STATS_PATH):
        with open(STATS_PATH, "rb") as f:
            original_stats = f.read()

    rng = secrets.SystemRandom()
    output_pattern = re.compile(
        r"Integral: ([+-]?\d+\.\d{4})\n"
        r"Mean: ([+-]?\d+\.\d{4})\n"
        r"Z-stat: ([+-]?\d+\.\d{4})"
    )

    try:
        for case_number in range(3):
            sequences = ["A" * rng.randint(7, 19), "G" * rng.randint(7, 19)]
            for _ in range(rng.randint(3, 7)):
                length = rng.randint(8, 31)
                sequences.append("".join(rng.choice("ACGT") for _ in range(length)))
            rng.shuffle(sequences)

            with open(FASTA_PATH, "w") as f:
                for i, sequence in enumerate(sequences):
                    f.write(f">dynamic_{case_number}_{i}\n{sequence}\n")

            expected = compute_expected_stats(FASTA_PATH)
            if os.path.exists(STATS_PATH):
                os.remove(STATS_PATH)

            result = subprocess.run(
                [EXE_PATH],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Compiled program failed on a FASTA input (exit {result.returncode}).\n"
                f"stderr:\n{result.stderr}"
            )
            assert os.path.isfile(STATS_PATH), (
                "Compiled program did not create /home/user/stats.txt."
            )

            with open(STATS_PATH, "r") as f:
                actual = f.read().strip()
            match = output_pattern.fullmatch(actual)
            assert match, (
                "Program output does not have the required three-line format with "
                f"exactly four decimal places:\n{actual}"
            )

            actual_values = tuple(float(value) for value in match.groups())
            for label, actual_value, expected_value in zip(
                ("Integral", "Mean", "Z-stat"), actual_values, expected
            ):
                assert abs(actual_value - expected_value) <= 0.000051, (
                    f"{label} is incorrect for a verifier-generated FASTA input: "
                    f"expected {expected_value:.4f}, got {actual_value:.4f}"
                )
    finally:
        with open(FASTA_PATH, "wb") as f:
            f.write(original_fasta)
        if original_stats is None:
            if os.path.exists(STATS_PATH):
                os.remove(STATS_PATH)
        else:
            with open(STATS_PATH, "wb") as f:
                f.write(original_stats)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
