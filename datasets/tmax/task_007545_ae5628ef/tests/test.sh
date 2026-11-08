#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess

import h5py
import numpy as np
import pytest

SOURCE = '/home/user/analyze_gc.c'
BINARY = '/tmp/analyze_gc_submission'
DATA_FILE = '/home/user/gc_data.h5'
RESULT_FILE = '/home/user/result.txt'
ORIGINAL = [0.2, 0.8, 0.4, 0.9, 0.3, 0.7, 0.5, 0.6, 0.1, 0.9]


def expected_lines(values):
    arr = [float(v) for v in values]
    diff = 1.0
    while diff >= 0.0001:
        new_arr = list(arr)
        for i in range(1, 9):
            new_arr[i] = 0.5 * arr[i] + 0.25 * arr[i - 1] + 0.25 * arr[i + 1]
        diff = max(abs(new_arr[i] - arr[i]) for i in range(10))
        arr = new_arr

    mean_val = sum(arr) / len(arr)
    return [
        f"Mean: {mean_val:.4f}",
        "Hypothesis: H1" if mean_val > 0.45 else "Hypothesis: H0",
    ]


def read_result():
    assert os.path.isfile(RESULT_FILE), f"Output file is missing: {RESULT_FILE}"
    with open(RESULT_FILE, 'r') as f:
        return [line.strip() for line in f.read().splitlines() if line.strip()]


@pytest.fixture(scope='session', autouse=True)
def compile_submission():
    assert os.path.isfile(SOURCE), f"C source file is missing: {SOURCE}"
    mode = os.stat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"C source is not a regular file: {SOURCE}"
    assert os.path.getsize(SOURCE) > 0, f"C source file is empty: {SOURCE}"

    proc = subprocess.run(
        ['h5cc', '-o', BINARY, SOURCE],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Failed to compile analyze_gc.c:\n{proc.stdout}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Compilation did not produce an executable"


def test_result_file_exists():
    """Check if the result file was created."""
    assert os.path.isfile(RESULT_FILE), f"Output file is missing: {RESULT_FILE}"


def test_result_file_contents():
    """Check if the contents of the result file match the expected computation."""
    expected_line1, expected_line2 = expected_lines(ORIGINAL)
    lines = read_result()

    assert len(lines) == 2, f"Expected exactly 2 lines in result.txt, but found {len(lines)}."
    assert lines[0] == expected_line1, f"Line 1 mismatch. Expected '{expected_line1}', got '{lines[0]}'."
    assert lines[1] == expected_line2, f"Line 2 mismatch. Expected '{expected_line2}', got '{lines[1]}'."


def test_program_reads_hdf5_and_computes_dynamic_inputs():
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    cases = [
        ORIGINAL,
        [rng.uniform(0.05, 0.35) for _ in range(10)],
        [rng.uniform(0.60, 0.95) for _ in range(10)],
        [rng.uniform(0.05, 0.95) for _ in range(10)],
    ]
    cases[1][0], cases[1][9] = rng.uniform(0.05, 0.20), rng.uniform(0.20, 0.35)
    cases[2][0], cases[2][9] = rng.uniform(0.65, 0.80), rng.uniform(0.80, 0.95)

    for values in cases:
        with h5py.File(DATA_FILE, 'w') as f:
            f.create_dataset('/gc_content', data=np.asarray(values, dtype=np.float64))

        if os.path.exists(RESULT_FILE):
            os.remove(RESULT_FILE)

        proc = subprocess.run(
            [BINARY],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        )
        assert proc.returncode == 0, f"Program exited with status {proc.returncode}:\n{proc.stdout}"

        expected = expected_lines(values)
        lines = read_result()
        assert len(lines) == 2, f"Expected exactly 2 lines in result.txt, but found {len(lines)}."
        assert lines[0] == expected[0], f"Line 1 mismatch. Expected '{expected[0]}', got '{lines[0]}'."
        assert lines[1] == expected[1], f"Line 2 mismatch. Expected '{expected[1]}', got '{lines[1]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
