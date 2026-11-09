#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

import numpy as np

C_FILE = Path('/home/user/cov_analyzer.c')
DATA_FILE = Path('/home/user/dataset.bin')
OUT_FILE = Path('/home/user/correlated_features.txt')
BINARY = Path('/tmp/cov_analyzer_verified')
N = 10000
M = 10


def test_c_program_exists():
    c_file = '/home/user/cov_analyzer.c'
    assert os.path.exists(c_file), f"The C program {c_file} does not exist."
    assert os.path.isfile(c_file), f"{c_file} is not a file."


def test_correlated_features_output():
    out_file = '/home/user/correlated_features.txt'
    assert os.path.exists(out_file), f"The output file {out_file} does not exist."
    assert os.path.isfile(out_file), f"{out_file} is not a file."

    with open(out_file, 'r') as f:
        content = f.read().strip()

    expected_lines = ["0,3", "2,7"]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {out_file} are incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(actual_lines)}"
    )


def expected_pairs(data):
    correlations = np.corrcoef(data, rowvar=False)
    return [
        f"{i},{j}"
        for i in range(M)
        for j in range(i + 1, M)
        if abs(float(correlations[i, j])) > 0.85
    ]


def read_output():
    assert OUT_FILE.exists(), f"Program did not create {OUT_FILE}"
    assert OUT_FILE.is_file(), f"{OUT_FILE} is not a regular file"
    lines = [line.strip() for line in OUT_FILE.read_text().splitlines() if line.strip()]
    for line in lines:
        assert re.fullmatch(r'[0-9]+,[0-9]+', line), f"Invalid output line: {line!r}"
        x, y = map(int, line.split(','))
        assert 0 <= x < y < M, f"Invalid feature pair: {line!r}"
    assert lines == sorted(lines, key=lambda line: tuple(map(int, line.split(',')))), \
        "Output pairs are not sorted by X, then Y"
    return lines


def run_and_check(data):
    DATA_FILE.write_bytes(np.asarray(data, dtype=np.float64, order='C').tobytes())
    if OUT_FILE.exists():
        OUT_FILE.unlink()
    result = subprocess.run(
        [str(BINARY)], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    actual = read_output()
    expected = expected_pairs(data)
    assert actual == expected, (
        f"Program produced incorrect correlations.\n"
        f"Expected: {expected}\nGot: {actual}"
    )


def test_program_compiles_and_computes_correlations():
    compile_result = subprocess.run(
        ['gcc', str(C_FILE), '-O2', '-o', str(BINARY), '-lm'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {C_FILE}.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), \
        "Compilation did not produce an executable"

    original_dataset = DATA_FILE.read_bytes()
    original_output = OUT_FILE.read_bytes()
    try:
        assert len(original_dataset) == N * M * 8, "Original dataset has an unexpected size"
        original_data = np.frombuffer(original_dataset, dtype=np.float64).reshape(N, M)
        run_and_check(original_data)

        rng = np.random.default_rng(secrets.randbits(128))
        for pair_count in (1, 3):
            data = rng.standard_normal((N, M))
            indices = rng.permutation(M)
            for k in range(pair_count):
                a = int(indices[2 * k])
                b = int(indices[2 * k + 1])
                sign = -1.0 if rng.integers(0, 2) else 1.0
                scale = rng.uniform(0.7, 2.5)
                data[:, b] = sign * scale * data[:, a] + rng.normal(0.0, 0.03, N)
            run_and_check(data)
    finally:
        DATA_FILE.write_bytes(original_dataset)
        OUT_FILE.write_bytes(original_output)
        if BINARY.exists():
            BINARY.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
