#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

PIPELINE = Path("/home/user/pipeline")
EXE = PIPELINE / "project"
SOURCE = PIPELINE / "project.c"
OUTPUT = PIPELINE / "output.txt"


def read_vector(path):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    assert len(rows) == 1
    return [float(value) for value in rows[0]]


def expected_for_files(directory):
    weights = read_vector(Path(directory) / "weights.csv")
    bias = read_vector(Path(directory) / "bias.csv")
    expected = []
    with open(Path(directory) / "input.csv", newline="") as f:
        for row in csv.reader(f):
            values = [float(value) for value in row]
            assert len(values) == len(weights) == len(bias) == 3
            result = sum((x - b) * w for x, b, w in zip(values, bias, weights))
            expected.append(f"{result:.2f}")
    return expected


def run_and_check(directory):
    output = Path(directory) / "output.txt"
    if output.exists():
        output.unlink()

    completed = subprocess.run(
        [str(EXE)], cwd=directory, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"Executable failed with code {completed.returncode}: {completed.stderr}"
    )
    assert output.is_file(), "Running the executable did not create output.txt."

    raw = output.read_text()
    actual = raw.splitlines()
    expected = expected_for_files(directory)
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} output lines, got {len(actual)}."
    )
    for index, (line, wanted) in enumerate(zip(actual, expected), 1):
        assert re.fullmatch(r"-?\d+\.\d{2}", line), (
            f"Line {index} is not formatted to exactly two decimal places: {line!r}"
        )
        assert line == wanted, (
            f"Line {index} is incorrect. Expected {wanted!r}, got {line!r}."
        )


def test_executable_exists_and_runnable():
    assert os.path.isfile(EXE), f"Compiled executable {EXE} is missing."
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "project must be a compiled ELF executable."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT), (
        f"Output file {OUTPUT} is missing. Did you run the executable?"
    )


def test_output_file_content():
    with open(OUTPUT, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ["1.40", "4.40", "7.40"]
    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in output.txt, but got {len(lines)}."
    )
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} in output.txt is incorrect. "
            f"Expected {expected!r}, got {actual!r}."
        )


def test_source_uses_gsl_blas_ddot():
    assert SOURCE.is_file(), f"Source file {SOURCE} is missing."
    source = SOURCE.read_text()
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)
    call = r"gsl_blas_ddot\s*\(\s*x\s*,\s*w\s*,\s*&\s*result\s*\)"
    assert re.search(call, source), (
        "project.c must call gsl_blas_ddot(x, w, &result) to compute the projection."
    )


def test_executable_recomputes_artifact_output():
    run_and_check(PIPELINE)


def test_executable_handles_unseen_inputs():
    rng = secrets.SystemRandom()
    for row_count in (2, 5):
        with tempfile.TemporaryDirectory() as temp_dir:
            directory = Path(temp_dir)
            weights = [rng.choice([-4, -3, -2, -1, 1, 2, 3, 4]) for _ in range(3)]
            bias = [rng.randint(-8, 8) for _ in range(3)]
            rows = [[rng.randint(-30, 30) for _ in range(3)] for _ in range(row_count)]

            (directory / "weights.csv").write_text(
                ",".join(map(str, weights)) + "\n"
            )
            (directory / "bias.csv").write_text(
                ",".join(map(str, bias)) + "\n"
            )
            (directory / "input.csv").write_text(
                "".join(",".join(map(str, row)) + "\n" for row in rows)
            )
            run_and_check(directory)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
