#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import ctypes
import subprocess

SRC = "/home/user/src/search.c"
EXE = "/home/user/src/search"
OUTPUT = "/home/user/output/recommendations.txt"
DATA = "/home/user/data/vectors.csv"


def expected_recommendations(seed):
    libc = ctypes.CDLL("libc.so.6")
    libc.srand(seed)
    M = [[0.0, 0.0] for _ in range(5)]
    for i in range(5):
        for j in range(2):
            M[i][j] = (libc.rand() % 1000) / 1000.0

    vectors = {}
    with open(DATA, "r") as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split(',')
            vectors[int(parts[0])] = [float(x) for x in parts[1:]]

    projected = {}
    for vec_id, vec in vectors.items():
        projected[vec_id] = (
            sum(vec[k] * M[k][0] for k in range(5)),
            sum(vec[k] * M[k][1] for k in range(5)),
        )

    assert 42 in projected, "Item with id=42 not found in dataset."
    target = projected[42]
    distances = []
    for vec_id, point in projected.items():
        if vec_id != 42:
            distance = math.sqrt((point[0] - target[0]) ** 2 + (point[1] - target[1]) ** 2)
            distances.append((vec_id, distance))
    distances.sort(key=lambda item: (item[1], item[0]))
    return [f"{vec_id},{distance:.4f}" for vec_id, distance in distances[:3]]


def test_c_source_and_executable_exist():
    assert os.path.isfile(SRC), f"C source file {SRC} is missing."
    assert os.path.isfile(EXE), f"Compiled executable {EXE} is missing."
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."


def test_submitted_program_and_recommendations():
    assert os.path.isfile(DATA), f"Data file {DATA} is missing."

    # Remove any precomputed answer and require the submitted executable to recreate it.
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run([EXE, "2024"], cwd="/home/user/src", capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"Submitted executable failed with exit code {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Executable did not create {OUTPUT}."

    with open(OUTPUT, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    expected_lines = expected_recommendations(2024)

    assert len(actual_lines) == 3, f"Expected exactly 3 lines in {OUTPUT}, but found {len(actual_lines)}."
    for i in range(3):
        assert actual_lines[i] == expected_lines[i], (
            f"Line {i+1} mismatch: expected '{expected_lines[i]}', got '{actual_lines[i]}'."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
