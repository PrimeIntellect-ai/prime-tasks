#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

SOURCE = "/home/user/analyze.c"
EXECUTABLE = "/home/user/analyze"
FASTA = "/home/user/sequences.fasta"
OUTPUT = "/home/user/regression.txt"


def expected_lines(sequences):
    x = [(i * 137 % 100000) / 10000.0 for i in range(100000)]
    mean_x = sum(x) / len(x)
    mean_x2 = sum(v ** 2 for v in x) / len(x)

    lengths = [len(seq) for seq in sequences]
    areas = []
    for seq in sequences:
        p = sum(1 for char in seq if char in "GC") / len(seq)
        areas.append((p * mean_x2 + (1 - p) * mean_x) * 10)

    n = len(lengths)
    sum_L = sum(lengths)
    sum_A = sum(areas)
    sum_LA = sum(length * area for length, area in zip(lengths, areas))
    sum_L2 = sum(length ** 2 for length in lengths)
    denominator = n * sum_L2 - sum_L ** 2
    assert denominator != 0
    slope = (n * sum_LA - sum_L * sum_A) / denominator
    intercept = (sum_A - slope * sum_L) / n
    return [f"Slope: {slope:.4f}", f"Intercept: {intercept:.4f}"]


def write_fasta(sequences, wrapped=False):
    with open(FASTA, "w") as handle:
        for index, sequence in enumerate(sequences):
            handle.write(f">seq{index + 1} generated test sequence\n")
            if wrapped:
                position = 0
                width = 1 + (index * 7) % 11
                while position < len(sequence):
                    handle.write(sequence[position:position + width] + "\n")
                    position += width
                    width = 1 + (width * 5 + 3) % 13
            else:
                handle.write(sequence + "\n")


def execute_and_read(sequences, wrapped=False):
    write_fasta(sequences, wrapped)
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)

    environment = os.environ.copy()
    environment["OMP_NUM_THREADS"] = "4"
    result = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."
    with open(OUTPUT) as handle:
        return [line.strip() for line in handle if line.strip()]


def test_submission_and_behavior():
    # Preserve the original artifact assertions before rebuilding from source.
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty."
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."

    with open(SOURCE, errors="replace") as handle:
        source_text = handle.read()
    pragma = re.compile(
        r"^[ \t]*#[ \t]*pragma[ \t]+omp[ \t]+parallel[ \t]+for(?:[ \t(]|$)",
        re.MULTILINE,
    )
    assert pragma.search(source_text), "analyze.c lacks the required #pragma omp parallel for directive."

    compile_result = subprocess.run(
        ["gcc", "-O2", "-fopenmp", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"analyze.c failed to compile with gcc -O2 -fopenmp:\n{compile_result.stderr}"
    )
    assert os.path.isfile(EXECUTABLE)
    assert os.access(EXECUTABLE, os.X_OK)

    # Retain the original fixed-data output assertion.
    original = [
        "ATGCGTA",
        "GCGCGCGCGC",
        "ATATATATATATAT",
        "GGGCCC",
        "ATGCATGCATGCATGC",
    ]
    lines = execute_and_read(original)
    expected = expected_lines(original)
    assert len(lines) == 2, f"Expected 2 lines in {OUTPUT}, found {len(lines)}"
    assert lines[0] == expected[0], f"Expected '{expected[0]}', got '{lines[0]}'"
    assert lines[1] == expected[1], f"Expected '{expected[1]}', got '{lines[1]}'"

    # Fresh, unpredictable inputs prevent a precomputed regression.txt from passing.
    rng = random.SystemRandom()
    for case_index in range(4):
        count = rng.randint(5, 9)
        lengths = rng.sample(range(5, 90), count)
        sequences = [
            "".join(rng.choice("ACGT") for _ in range(length))
            for length in lengths
        ]
        expected = expected_lines(sequences)
        lines = execute_and_read(sequences, wrapped=(case_index % 2 == 0))
        assert len(lines) == 2, f"Expected exactly 2 nonempty output lines, got {lines!r}"
        assert lines == expected, f"For generated FASTA, expected {expected!r}, got {lines!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
