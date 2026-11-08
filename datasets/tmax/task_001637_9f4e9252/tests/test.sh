#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
from pathlib import Path
import random
import subprocess

HYDROPHOBICITY = {
    "A": 1.8, "R": -4.5, "N": -3.5, "D": -3.5, "C": 2.5,
    "Q": -3.5, "E": -3.5, "G": -0.4, "H": -3.2, "I": 4.5,
    "L": 3.8, "K": -3.9, "M": 1.9, "F": 2.8, "P": -1.6,
    "S": -0.8, "T": -0.7, "W": -0.9, "Y": -1.3, "V": 4.2,
}

FASTA_PATH = "/home/user/proteins.fasta"
CSV_PATH = "/home/user/features.csv"
VENV_DIR = "/home/user/venv"
PYTHON_EXEC = os.path.join(VENV_DIR, "bin", "python")


def parse_fasta(path):
    records = []
    current_id = None
    sequence_parts = []
    with open(path, "r") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current_id is not None:
                    records.append((current_id, "".join(sequence_parts)))
                current_id = line[1:]
                sequence_parts = []
            else:
                assert current_id is not None, "Sequence data appeared before a FASTA header."
                sequence_parts.append(line)
    if current_id is not None:
        records.append((current_id, "".join(sequence_parts)))
    return records


def expected_energy(sequence):
    values = [HYDROPHOBICITY[amino_acid] for amino_acid in sequence]
    n = len(values)
    positive_power = []
    for k in range(1, n // 2 + 1):
        real = 0.0
        imag = 0.0
        for position, value in enumerate(values):
            angle = -2.0 * math.pi * k * position / n
            real += value * math.cos(angle)
            imag += value * math.sin(angle)
        positive_power.append(real * real + imag * imag)

    # Composite trapezoidal rule with dx=1.0.
    return sum(
        (positive_power[index] + positive_power[index + 1]) / 2.0
        for index in range(len(positive_power) - 1)
    )


def assert_features_match(records, csv_path=CSV_PATH):
    assert os.path.isfile(csv_path), f"Output file {csv_path} does not exist."
    with open(csv_path, "r", newline="") as handle:
        nonblank_lines = [line for line in handle if line.strip()]

    rows = list(csv.reader(nonblank_lines))
    assert len(rows) == len(records) + 1, (
        f"Expected {len(records) + 1} non-empty CSV rows, got {len(rows)}."
    )
    assert rows[0] == ["Sequence_ID", "Total_Energy"], (
        "CSV must have exactly the columns Sequence_ID and Total_Energy."
    )

    expected_rows = [
        [sequence_id, f"{expected_energy(sequence):.2f}"]
        for sequence_id, sequence in records
    ]
    for index, (actual, expected) in enumerate(zip(rows[1:], expected_rows), start=2):
        assert actual == expected, (
            f"Line {index} mismatch. Expected {expected!r}, got {actual!r}."
        )


def test_venv_and_packages():
    assert os.path.isdir(VENV_DIR), f"Virtual environment directory {VENV_DIR} does not exist."
    assert os.path.isfile(PYTHON_EXEC), f"Python executable not found at {PYTHON_EXEC}."

    result = subprocess.run([PYTHON_EXEC, "-c", "import numpy"], capture_output=True)
    assert result.returncode == 0, "numpy is not installed in the virtual environment."

    result = subprocess.run([PYTHON_EXEC, "-c", "import scipy"], capture_output=True)
    assert result.returncode == 0, "scipy is not installed in the virtual environment."


def test_features_csv_content():
    records = parse_fasta(FASTA_PATH)
    assert_features_match(records)


def test_python_script_recomputes_features_for_new_input():
    candidates = []
    venv_prefix = os.path.realpath(VENV_DIR) + os.sep
    for path in Path("/home/user").rglob("*"):
        if not path.is_file() or os.path.realpath(str(path)).startswith(venv_prefix):
            continue
        if str(path) in (FASTA_PATH, CSV_PATH):
            continue
        is_python = path.suffix == ".py"
        if not is_python:
            try:
                with path.open("rb") as handle:
                    first_line = handle.readline(256).lower()
                is_python = first_line.startswith(b"#!") and b"python" in first_line
            except OSError:
                is_python = False
        if is_python:
            candidates.append(str(path))

    assert candidates, "No Python analysis script was found under /home/user."

    rng = random.SystemRandom()
    alphabet = list(HYDROPHOBICITY)
    nonce = rng.randrange(10**8, 10**9)
    records = []
    for index, length in enumerate((31, 48, 57), start=1):
        sequence = "".join(rng.choice(alphabet) for _ in range(length))
        records.append((f"Verifier_{nonce}_{index}", sequence))

    fasta_text_parts = []
    for sequence_id, sequence in records:
        fasta_text_parts.append(f">{sequence_id}\n")
        # Exercise multiline FASTA parsing.
        for start in range(0, len(sequence), 13):
            fasta_text_parts.append(sequence[start:start + 13] + "\n")
    fasta_text = "".join(fasta_text_parts)

    with open(FASTA_PATH, "rb") as handle:
        original_fasta = handle.read()
    original_csv = None
    if os.path.exists(CSV_PATH):
        with open(CSV_PATH, "rb") as handle:
            original_csv = handle.read()

    errors = []
    succeeded = False
    try:
        for candidate in candidates:
            with open(FASTA_PATH, "w") as handle:
                handle.write(fasta_text)
            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)

            try:
                result = subprocess.run(
                    [PYTHON_EXEC, candidate],
                    cwd="/home/user",
                    capture_output=True,
                    text=True,
                    timeout=60,
                )
                assert result.returncode == 0, (
                    f"exited with status {result.returncode}: {result.stderr[-500:]}"
                )
                assert_features_match(records)
                succeeded = True
                break
            except Exception as exc:
                errors.append(f"{candidate}: {exc}")
    finally:
        with open(FASTA_PATH, "wb") as handle:
            handle.write(original_fasta)
        if original_csv is None:
            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)
        else:
            with open(CSV_PATH, "wb") as handle:
                handle.write(original_csv)

    assert succeeded, "No submitted Python script correctly recomputed the features. " + " | ".join(errors)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
