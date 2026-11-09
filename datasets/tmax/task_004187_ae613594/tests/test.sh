#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import math
import os
import secrets
import stat
import subprocess
from pathlib import Path

import numpy as np

MATRICES = Path('/home/user/matrices.txt')
SEQUENCE = Path('/home/user/sequence.txt')
SOURCE = Path('/home/user/calc_prob.cpp')
EXECUTABLE = Path('/home/user/calc_prob')
RESULT = Path('/home/user/result.txt')


def original_fixtures():
    np.random.seed(42)
    matrices = []
    for _ in range(100):
        mat = np.random.rand(4, 4)
        mat[0, 3] = 0.0
        mat[1, 1] = 0.0
        row_sums = mat.sum(axis=1)
        mat = mat / row_sums[:, np.newaxis]
        matrices.append(mat)

    matrix_out = io.StringIO()
    for mat in matrices:
        for row in mat:
            matrix_out.write(' '.join(f'{x:.6f}' for x in row) + '\n')

    bases = ['A', 'C', 'G', 'T']
    seq = ['A']
    for _ in range(499):
        curr = seq[-1]
        if curr == 'A':
            seq.append(np.random.choice(['A', 'C', 'G']))
        elif curr == 'C':
            seq.append(np.random.choice(['A', 'G', 'T']))
        else:
            seq.append(np.random.choice(bases))

    return matrix_out.getvalue().encode(), (''.join(seq) + '\n').encode()


def expected_result(matrix_bytes, sequence_bytes):
    nums = [float(x) for x in matrix_bytes.decode().split()]
    assert len(nums) == 1600, 'matrices.txt should contain 1600 numbers.'

    seq = sequence_bytes.decode().strip()
    base_to_idx = {'A': 0, 'C': 1, 'G': 2, 'T': 3}
    seq_idx = [base_to_idx[b] for b in seq]

    log_probs = []
    for m in range(100):
        lp = 0.0
        for i in range(1, len(seq_idx)):
            u = seq_idx[i - 1]
            v = seq_idx[i]
            prob = nums[m * 16 + u * 4 + v]
            if prob == 0.0:
                lp = -float('inf')
                break
            lp += math.log(prob)
        log_probs.append(lp)

    log_probs.sort()
    return f'[{log_probs[2]:.4f}, {log_probs[97]:.4f}]'


def serialize_matrices(matrices):
    lines = []
    for mat in matrices:
        for row in mat:
            lines.append(' '.join(f'{x:.6f}' for x in row))
    return ('\n'.join(lines) + '\n').encode()


def make_runtime_cases():
    rng = secrets.SystemRandom()
    matrices = []
    for _ in range(100):
        mat = []
        for _ in range(4):
            values = [rng.uniform(0.1, 1.1) for _ in range(4)]
            total = sum(values)
            mat.append([v / total for v in values])
        matrices.append(mat)

    # A runtime-generated sequence makes hard-coded fixture answers insufficient.
    seq = ''.join(rng.choice('ACGT') for _ in range(500))
    positive = (serialize_matrices(matrices), (seq + '\n').encode())

    # Exercise missing-edge handling without making either requested percentile
    # infinite: exactly two matrices have a missing edge used by the sequence.
    zero_matrices = [[row[:] for row in mat] for mat in matrices]
    idx = {'A': 0, 'C': 1, 'G': 2, 'T': 3}
    u, v = idx[seq[0]], idx[seq[1]]
    zero_matrices[0][u][v] = 0.0
    zero_matrices[1][u][v] = 0.0
    with_zeros = (serialize_matrices(zero_matrices), (seq + '\n').encode())
    return [positive, with_zeros]


def run_and_check(binary, matrix_bytes, sequence_bytes):
    MATRICES.write_bytes(matrix_bytes)
    SEQUENCE.write_bytes(sequence_bytes)
    if RESULT.exists() or RESULT.is_symlink():
        RESULT.unlink()

    completed = subprocess.run(
        [str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert completed.returncode == 0, (
        f'{binary} exited with {completed.returncode}. stderr: {completed.stderr}'
    )
    assert RESULT.is_file(), f'{binary} did not generate /home/user/result.txt'
    assert not RESULT.is_symlink(), '/home/user/result.txt must be a regular file'
    actual = RESULT.read_text().strip()
    expected = expected_result(matrix_bytes, sequence_bytes)
    assert actual == expected, f"Expected output '{expected}', but got '{actual}'"
    assert MATRICES.read_bytes() == matrix_bytes, f'{binary} modified matrices.txt'
    assert SEQUENCE.read_bytes() == sequence_bytes, f'{binary} modified sequence.txt'


def test_result_file_exists():
    """Test that the result file was generated."""
    assert os.path.isfile('/home/user/result.txt'), '/home/user/result.txt does not exist.'


def test_original_fixtures_are_unchanged():
    expected_matrices, expected_sequence = original_fixtures()
    assert MATRICES.is_file() and not MATRICES.is_symlink(), 'matrices.txt must be the provided regular file.'
    assert SEQUENCE.is_file() and not SEQUENCE.is_symlink(), 'sequence.txt must be the provided regular file.'
    assert MATRICES.read_bytes() == expected_matrices, 'The provided matrices.txt fixture was modified.'
    assert SEQUENCE.read_bytes() == expected_sequence, 'The provided sequence.txt fixture was modified.'


def test_result_accuracy():
    """Test that the computed confidence interval is correct."""
    matrices_path = '/home/user/matrices.txt'
    assert os.path.isfile(matrices_path), f'{matrices_path} is missing.'
    with open(matrices_path, 'r') as f:
        nums = [float(x) for x in f.read().split()]
    assert len(nums) == 1600, 'matrices.txt should contain 1600 numbers.'

    matrices = []
    for m in range(100):
        mat = []
        for i in range(4):
            row = []
            for j in range(4):
                row.append(nums[m * 16 + i * 4 + j])
            mat.append(row)
        matrices.append(mat)

    seq_path = '/home/user/sequence.txt'
    assert os.path.isfile(seq_path), f'{seq_path} is missing.'
    with open(seq_path, 'r') as f:
        seq = f.read().strip()

    base_to_idx = {'A': 0, 'C': 1, 'G': 2, 'T': 3}
    seq_idx = [base_to_idx[b] for b in seq]
    log_probs = []
    for mat in matrices:
        lp = 0.0
        for i in range(1, len(seq_idx)):
            u = seq_idx[i - 1]
            v = seq_idx[i]
            prob = mat[u][v]
            if prob == 0.0:
                lp = -float('inf')
                break
            lp += math.log(prob)
        log_probs.append(lp)

    log_probs.sort()
    expected_lower = log_probs[2]
    expected_upper = log_probs[97]
    expected_str = f'[{expected_lower:.4f}, {expected_upper:.4f}]'

    result_path = '/home/user/result.txt'
    assert os.path.isfile(result_path), f'{result_path} is missing.'
    with open(result_path, 'r') as f:
        actual_str = f.read().strip()
    assert actual_str == expected_str, f"Expected output '{expected_str}', but got '{actual_str}' in {result_path}."


def test_source_and_executable_work_on_derived_inputs(tmp_path):
    assert SOURCE.is_file() and not SOURCE.is_symlink(), 'calc_prob.cpp is missing or is not a regular file.'
    assert EXECUTABLE.is_file() and not EXECUTABLE.is_symlink(), 'calc_prob executable is missing or is not a regular file.'
    mode = EXECUTABLE.stat().st_mode
    assert stat.S_ISREG(mode) and os.access(EXECUTABLE, os.X_OK), 'calc_prob is not an executable regular file.'

    original_matrices, original_sequence = original_fixtures()
    rebuilt = tmp_path / 'calc_prob_rebuilt'
    compile_result = subprocess.run(
        ['g++', '-O3', '-std=c++11', str(SOURCE), '-o', str(rebuilt)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f'calc_prob.cpp did not compile: {compile_result.stderr}'

    cases = [(original_matrices, original_sequence)] + make_runtime_cases()
    try:
        for binary in (EXECUTABLE, rebuilt):
            for matrix_bytes, sequence_bytes in cases:
                run_and_check(binary, matrix_bytes, sequence_bytes)
    finally:
        MATRICES.write_bytes(original_matrices)
        SEQUENCE.write_bytes(original_sequence)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
