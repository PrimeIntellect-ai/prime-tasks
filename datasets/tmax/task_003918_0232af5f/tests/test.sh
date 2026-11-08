#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

C_PATH = "/home/user/sim/sub_matrix.c"
FASTA_PATH = "/home/user/data/alignment.fasta"
OUTPUT_PATH = "/home/user/fixed_matrix.txt"
BUILD_DIR = tempfile.mkdtemp(prefix="sub_matrix_verify_")
BINARY_PATH = os.path.join(BUILD_DIR, "sub_matrix")


def parse_fasta(path):
    records = []
    current = []
    with open(path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current:
                    records.append("".join(current))
                    current = []
            else:
                current.append(line)
    if current:
        records.append("".join(current))
    assert len(records) == 2, f"Expected exactly two FASTA records, found {len(records)}."
    return records


def expected_matrix(seq1, seq2):
    index = {"A": 0, "C": 1, "G": 2, "T": 3}
    matrix = [[1 for _ in range(4)] for _ in range(4)]
    for left, right in zip(seq1, seq2):
        matrix[index[left]][index[right]] += 1
    return [[value / sum(row) for value in row] for row in matrix]


def parse_program_output(text):
    lines = text.strip().splitlines()
    assert len(lines) == 4, f"Expected 4 output rows, got {len(lines)}. Output was: {text!r}"
    parsed = []
    number = re.compile(r"^[+-]?\d+\.\d{4}$")
    for i, line in enumerate(lines):
        tokens = line.strip().split()
        assert len(tokens) == 4, f"Expected 4 values in row {i + 1}, got {len(tokens)}."
        for token in tokens:
            assert number.fullmatch(token), f"Value {token!r} is not a float with exactly 4 decimal places."
        parsed.append([float(token) for token in tokens])
    return parsed


def assert_matrix_matches(actual, expected):
    for i in range(4):
        for j in range(4):
            assert abs(actual[i][j] - expected[i][j]) <= 0.000051, \
                f"Value at row {i + 1}, col {j + 1} is {actual[i][j]:.4f}, expected {expected[i][j]:.4f}."


def compile_program():
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_PATH, "-o", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"C source did not compile:\n{result.stderr}"
    assert os.path.isfile(BINARY_PATH), "Compilation did not produce a binary."
    assert os.access(BINARY_PATH, os.X_OK), "Compiled program is not executable."


def run_program(seq1, seq2):
    result = subprocess.run(
        [BINARY_PATH, seq1, seq2],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, \
        f"Program exited with status {result.returncode}: {result.stderr.decode(errors='replace')}"
    return result.stdout


def test_fixed_matrix_exists():
    assert os.path.isfile(OUTPUT_PATH), \
        f"Output file {OUTPUT_PATH} does not exist. Did you run the program and redirect the output?"


def test_fixed_matrix_content():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 4, f"Expected 4 rows in {OUTPUT_PATH}, but got {len(lines)}."

    expected_matrix_values = [
        [0.8500, 0.0500, 0.0500, 0.0500],
        [0.2500, 0.2500, 0.2500, 0.2500],
        [0.0500, 0.0500, 0.4500, 0.4500],
        [0.2500, 0.2500, 0.2500, 0.2500],
    ]

    for i, line in enumerate(lines):
        values = line.strip().split()
        assert len(values) == 4, f"Expected 4 values in row {i + 1}, but got {len(values)}."
        for j, val in enumerate(values):
            try:
                float_val = float(val)
            except ValueError:
                pytest.fail(f"Value '{val}' in row {i + 1} is not a valid float.")
            expected_val = expected_matrix_values[i][j]
            assert abs(float_val - expected_val) < 1e-4, \
                f"Value at row {i + 1}, col {j + 1} is {float_val:.4f}, expected {expected_val:.4f}. Laplace smoothing (+1) may not have been applied correctly."

    seq1, seq2 = parse_fasta(FASTA_PATH)
    assert_matrix_matches(parse_program_output("\n".join(lines)), expected_matrix(seq1, seq2))


def test_c_file_modified():
    assert os.path.isfile(C_PATH), f"File {C_PATH} does not exist."
    with open(C_PATH, "r") as f:
        content = f.read()
    assert "matrix[4][4]" in content, "Matrix declaration missing."


def test_source_compiles_and_reproduces_redirected_output():
    compile_program()
    seq1, seq2 = parse_fasta(FASTA_PATH)
    stdout = run_program(seq1, seq2)
    with open(OUTPUT_PATH, "rb") as f:
        saved_output = f.read()
    assert stdout == saved_output, \
        f"{OUTPUT_PATH} is not exactly the standard output of the compiled program for the two FASTA sequences."
    assert_matrix_matches(parse_program_output(stdout.decode()), expected_matrix(seq1, seq2))


def test_program_laplace_smoothing_and_mapping_on_independent_inputs():
    if not os.path.isfile(BINARY_PATH):
        compile_program()

    alphabet = "ACGT"
    cases = [
        ("A" * 13, "ACGTACGTACGTA"),
        ("AAAACCCCGGGGTTTT", "".join(secrets.choice(alphabet) for _ in range(16))),
    ]
    for length in (29, 37, 43):
        cases.append((
            "".join(secrets.choice(alphabet) for _ in range(length)),
            "".join(secrets.choice(alphabet) for _ in range(length)),
        ))

    for seq1, seq2 in cases:
        output = run_program(seq1, seq2).decode()
        actual = parse_program_output(output)
        assert_matrix_matches(actual, expected_matrix(seq1, seq2))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
