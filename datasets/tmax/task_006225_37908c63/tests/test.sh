#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import random
import subprocess
from pathlib import Path

PRIMER = "GATCGATCG"
ORIGINAL_SEQS = [
    "GATCGATCGAAT",
    "ATATATATATAT",
    "GCGCGCGCGCGC",
    "GATCGATCGGGC",
    "TTTTTTTTTTTT",
    "GATCGATC",
    "GATCGATCG",
    "CCCGGGCCCGGG"
]


def calculate_data(seqs):
    expected_csv = [["sequence", "gc_percentage", "group", "binding_score"]]
    group_a_scores = []
    group_b_scores = []

    for seq in seqs:
        gc_count = sum(1 for c in seq if c in "GC")
        gc_percentage = (gc_count / len(seq)) * 100.0
        group = "A" if gc_percentage >= 50.0 else "B"

        if len(seq) < len(PRIMER):
            max_m = 0
        else:
            max_m = max(
                sum(1 for a, b in zip(seq[i:i + len(PRIMER)], PRIMER) if a == b)
                for i in range(len(seq) - len(PRIMER) + 1)
            )

        expected_csv.append([seq, f"{gc_percentage:.2f}", group, str(max_m)])
        if group == "A":
            group_a_scores.append(max_m)
        else:
            group_b_scores.append(max_m)

    mean_a = sum(group_a_scores) / len(group_a_scores) if group_a_scores else 0.0
    mean_b = sum(group_b_scores) / len(group_b_scores) if group_b_scores else 0.0
    expected_stats = [
        f"Mean Score A: {mean_a:.2f}",
        f"Mean Score B: {mean_b:.2f}",
        f"Significant Difference: {str(abs(mean_a - mean_b) > 1.0).lower()}"
    ]
    return expected_csv, expected_stats


def calculate_expected_data():
    return calculate_data(ORIGINAL_SEQS)


def read_csv(path):
    with open(path, "r", newline="") as f:
        return list(csv.reader(f))


def read_stats(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def assert_outputs(seqs):
    csv_path = "/home/user/training_data.csv"
    stats_path = "/home/user/stats.txt"
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."
    assert os.path.isfile(stats_path), f"Output file {stats_path} is missing."

    expected_csv, expected_stats = calculate_data(seqs)
    actual_csv = read_csv(csv_path)
    actual_stats = read_stats(stats_path)

    assert len(actual_csv) == len(expected_csv), f"Expected {len(expected_csv)} lines in CSV, got {len(actual_csv)}."
    for i, (actual_row, expected_row) in enumerate(zip(actual_csv, expected_csv)):
        assert actual_row == expected_row, f"Mismatch at CSV row {i + 1}. Expected {expected_row}, got {actual_row}."

    assert len(actual_stats) == len(expected_stats), f"Expected {len(expected_stats)} lines in stats.txt, got {len(actual_stats)}."
    for i, (actual_line, expected_line) in enumerate(zip(actual_stats, expected_stats)):
        assert actual_line.lower() == expected_line.lower(), f"Mismatch at stats.txt line {i + 1}. Expected '{expected_line}', got '{actual_line}'."


def test_cpp_file_exists():
    assert os.path.isfile("/home/user/prepare_data.cpp"), "Source code file /home/user/prepare_data.cpp is missing."


def test_training_data_csv():
    csv_path = "/home/user/training_data.csv"
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."
    expected_csv, _ = calculate_expected_data()
    actual_csv = read_csv(csv_path)
    assert len(actual_csv) == len(expected_csv), f"Expected {len(expected_csv)} lines in CSV, got {len(actual_csv)}."
    for i, (actual_row, expected_row) in enumerate(zip(actual_csv, expected_csv)):
        assert actual_row == expected_row, f"Mismatch at CSV row {i + 1}. Expected {expected_row}, got {actual_row}."


def test_stats_txt():
    stats_path = "/home/user/stats.txt"
    assert os.path.isfile(stats_path), f"Output file {stats_path} is missing."
    _, expected_stats = calculate_expected_data()
    actual_stats = read_stats(stats_path)
    assert len(actual_stats) == len(expected_stats), f"Expected {len(expected_stats)} lines in stats.txt, got {len(actual_stats)}."
    for i, (actual_line, expected_line) in enumerate(zip(actual_stats, expected_stats)):
        assert actual_line.lower() == expected_line.lower(), f"Mismatch at stats.txt line {i + 1}. Expected '{expected_line}', got '{actual_line}'."


def test_compiled_program_processes_unseen_inputs():
    source = "/home/user/prepare_data.cpp"
    executable = "/tmp/prepare_data_verified"
    compile_result = subprocess.run(
        ["g++", "-std=c++11", "-O2", source, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30
    )
    assert compile_result.returncode == 0, f"C++ source did not compile:\n{compile_result.stderr}"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Compilation did not produce an executable."

    seq_path = Path("/home/user/sequences.txt")
    csv_path = Path("/home/user/training_data.csv")
    stats_path = Path("/home/user/stats.txt")
    original_seq_bytes = seq_path.read_bytes()
    original_csv_bytes = csv_path.read_bytes()
    original_stats_bytes = stats_path.read_bytes()
    rng = random.SystemRandom()

    try:
        for _ in range(2):
            rand = lambda alphabet, n: "".join(rng.choice(alphabet) for _ in range(n))
            mutated = list(PRIMER)
            for index in rng.sample(range(len(PRIMER)), 3):
                mutated[index] = rng.choice([c for c in "ACGT" if c != mutated[index]])

            seqs = [
                rand("GC", 12),
                rand("AT", 12),
                rand("ACGT", 8),
                rand("ACGT", 3) + PRIMER + rand("ACGT", 4),
                rand("ACGT", 2) + "".join(mutated) + rand("ACGT", 5),
                rand("GCGCAT", 20),
                rand("ATATGC", 20),
                rand("ACGT", 9),
                rand("GC", 10),
                rand("AT", 10)
            ]
            rng.shuffle(seqs)
            seq_path.write_text("\n".join(seqs) + "\n")
            if csv_path.exists():
                csv_path.unlink()
            if stats_path.exists():
                stats_path.unlink()

            run_result = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15
            )
            assert run_result.returncode == 0, f"Compiled program failed when executed:\n{run_result.stderr}"
            assert_outputs(seqs)
    finally:
        seq_path.write_bytes(original_seq_bytes)
        csv_path.write_bytes(original_csv_bytes)
        stats_path.write_bytes(original_stats_bytes)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
