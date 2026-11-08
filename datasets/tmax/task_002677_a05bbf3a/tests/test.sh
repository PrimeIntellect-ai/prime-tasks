#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess

from scipy import optimize

PREPARE = "/home/user/prepare_data.py"
PIPELINE = "/home/user/run_pipeline.sh"
OUTPUT = "/home/user/training_data.csv"
REFERENCE = "/home/user/reference.fasta"
CANDIDATES = "/home/user/candidates.txt"


def expected_x(length, gc):
    def equation(values):
        x = float(values[0])
        return [math.exp(x / length) + x * math.log(gc + 0.1) - 10]

    root = float(optimize.fsolve(equation, [1.0])[0])
    return root


def read_rows():
    with open(OUTPUT, "r", newline="") as f:
        return list(csv.reader(f))


def assert_output(expected):
    rows = read_rows()
    assert len(rows) > 0, "CSV file is empty."

    expected_header = ["sequence", "L", "GC", "x"]
    assert rows[0] == expected_header, (
        f"Header mismatch. Expected {expected_header}, got {rows[0]}"
    )

    data_rows = rows[1:]
    assert len(data_rows) == len(expected), (
        f"Expected {len(expected)} rows, got {len(data_rows)}"
    )

    for i, (row, (expected_sequence, expected_length)) in enumerate(zip(data_rows, expected)):
        assert len(row) == 4, f"Row {i + 1} does not have 4 columns."
        sequence, length_text, gc_text, x_text = row

        assert sequence == expected_sequence, (
            f"Row {i + 1} sequence mismatch. Expected {expected_sequence}, got {sequence}"
        )

        try:
            length_value = int(length_text)
            gc_value = float(gc_text)
            x_value = float(x_text)
        except ValueError:
            assert False, f"Row {i + 1} contains invalid numeric values: {row}"

        gc_expected = (expected_sequence.count("G") + expected_sequence.count("C")) / expected_length
        x_expected = expected_x(expected_length, gc_expected)

        assert length_value == expected_length, (
            f"Row {i + 1} L mismatch. Expected {expected_length}, got {length_value}"
        )
        assert re.fullmatch(r"[+-]?\d+\.\d{4}", gc_text), (
            f"Row {i + 1} GC must have exactly 4 decimal places, got {gc_text}"
        )
        assert re.fullmatch(r"[+-]?\d+\.\d{4}", x_text), (
            f"Row {i + 1} x must have exactly 4 decimal places, got {x_text}"
        )
        assert math.isclose(gc_value, gc_expected, abs_tol=1e-4), (
            f"Row {i + 1} GC mismatch. Expected {gc_expected:.4f}, got {gc_value}"
        )
        assert math.isclose(x_value, x_expected, abs_tol=1e-4), (
            f"Row {i + 1} x mismatch. Expected {x_expected:.4f}, got {x_value}"
        )
        assert gc_text == f"{gc_expected:.4f}"
        assert x_text == f"{x_expected:.4f}"


def run(command):
    result = subprocess.run(command, cwd="/home/user", text=True, capture_output=True)
    assert result.returncode == 0, (
        f"Command failed: {' '.join(command)}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{OUTPUT} was not generated."


def test_files_exist():
    assert os.path.isfile(PREPARE), f"{PREPARE} is missing."
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is missing."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is missing."


def test_pipeline_executable():
    assert os.access(PIPELINE, os.X_OK), f"{PIPELINE} must be executable."


def test_scripts_are_valid_and_connected():
    subprocess.run(["python3", "-m", "py_compile", PREPARE], check=True)
    subprocess.run(["bash", "-n", PIPELINE], check=True)
    with open(PIPELINE, "r") as f:
        active_lines = [line.split("#", 1)[0] for line in f]
    assert any("prepare_data.py" in line for line in active_lines), (
        "run_pipeline.sh must execute prepare_data.py"
    )


def test_csv_output_from_pipeline():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run(["bash", PIPELINE])
    assert_output([
        ("CGTAGCTAGC", 10),
        ("ATCGATCGAT", 10),
        ("CTAGCATCGA", 10),
    ])


def test_python_and_pipeline_on_derived_fixture():
    saved_reference = open(REFERENCE, "rb").read()
    saved_candidates = open(CANDIDATES, "rb").read()
    saved_output = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None

    try:
        rng = random.SystemRandom()
        while True:
            genome = "".join(rng.choice("ACGT") for _ in range(180))
            valid = [genome[7:15], genome[51:62], genome[119:133]]
            if len(set(valid)) == 3:
                break

        invalid = []
        while len(invalid) < 2:
            candidate = "".join(rng.choice("ACGT") for _ in range(9 + len(invalid)))
            if candidate not in genome and candidate not in invalid:
                invalid.append(candidate)

        ordered_candidates = [valid[1], invalid[0], valid[0], invalid[1], valid[2]]
        expected = [(valid[1], len(valid[1])), (valid[0], len(valid[0])), (valid[2], len(valid[2]))]

        with open(REFERENCE, "w") as f:
            f.write(">dynamic_reference\n")
            for offset in range(0, len(genome), 37):
                f.write(genome[offset:offset + 37] + "\n")
        with open(CANDIDATES, "w") as f:
            f.write("\n".join(ordered_candidates) + "\n")

        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        run(["python3", PREPARE])
        assert_output(expected)

        os.remove(OUTPUT)
        run(["bash", PIPELINE])
        assert_output(expected)
    finally:
        with open(REFERENCE, "wb") as f:
            f.write(saved_reference)
        with open(CANDIDATES, "wb") as f:
            f.write(saved_candidates)
        if saved_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(saved_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
