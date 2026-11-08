#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import secrets
import subprocess
import tempfile
import pytest


def test_evaluate_rs_exists():
    path = "/home/user/evaluate.rs"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "fn main" in content, "evaluate.rs does not appear to be a valid Rust program (missing fn main)."


def test_evaluate_executable_exists():
    path = "/home/user/evaluate"
    assert os.path.isfile(path), f"Executable missing: {path}"
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled executable."


def test_valid_ids_content():
    path = "/home/user/valid_ids.txt"
    assert os.path.isfile(path), f"File missing: {path}"

    expected_ids = ["1", "2", "3", "5", "7"]

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_ids, f"Content of {path} does not match the expected valid IDs. Got {lines}, expected {expected_ids}."


def test_experiment_log_content():
    path = "/home/user/experiment_log.txt"
    assert os.path.isfile(path), f"File missing: {path}"

    expected_log = "Run 1: 5 valid models"

    with open(path, "r") as f:
        content = f.read().strip()

    assert expected_log in content, f"Expected '{expected_log}' to be in {path}, but got '{content}'."


def exercise_evaluator(path):
    rng = secrets.SystemRandom()
    first_id = rng.randrange(1000000, 9000000)
    rows = []

    # Explicitly exercise equality, both strict boundaries, and values on both
    # sides of the threshold. Additional unpredictable cases prevent a fixed
    # output implementation from satisfying this test.
    fixed = [
        (10.0, 10.0),
        (10.0, 10.999),
        (10.0, 9.001),
        (10.0, 11.0),
        (10.0, 9.0),
        (-12.5, -11.6),
        (-12.5, -13.6),
    ]
    for i, (prediction, actual) in enumerate(fixed):
        rows.append((str(first_id + i), repr(prediction), repr(actual)))

    deltas = [-2.25, -1.0, -0.875, -0.25, 0.0, 0.375, 0.999, 1.0, 1.75]
    for i in range(len(fixed), 47):
        prediction = rng.randrange(-100000, 100001) / 8.0
        actual = prediction + rng.choice(deltas)
        rows.append((str(first_id + i), repr(prediction), repr(actual)))

    input_text = "".join(f"{ident} {pred} {actual}\n" for ident, pred, actual in rows)
    expected = [
        ident for ident, pred, actual in rows
        if abs(float(pred) - float(actual)) < 1.0
    ]

    result = subprocess.run(
        [path],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Evaluator {path} exited with {result.returncode}. stderr: {result.stderr}"
    )
    actual_output = result.stdout.splitlines()
    assert actual_output == expected, (
        f"Evaluator {path} produced {actual_output}, expected {expected}."
    )


def test_submitted_executable_behavior():
    exercise_evaluator("/home/user/evaluate")


def test_rust_source_compiles_and_behaves():
    with tempfile.TemporaryDirectory() as tempdir:
        rebuilt = os.path.join(tempdir, "evaluate")
        result = subprocess.run(
            ["rustc", "/home/user/evaluate.rs", "-o", rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"evaluate.rs failed to compile with rustc. stderr: {result.stderr}"
        )
        exercise_evaluator(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
