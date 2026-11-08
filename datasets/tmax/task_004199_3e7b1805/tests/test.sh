#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import secrets
import subprocess
import sys

import numpy as np
import pytest

SCRIPT = '/home/user/analyze_kmers.py'
FASTA = '/home/user/data/seqs.fasta'
SVD_OUT = '/home/user/svd_out.txt'
W_SUM_OUT = '/home/user/w_sum.txt'


def read_fasta(path):
    sequences = []
    current = []
    with open(path, 'r') as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith('>'):
                if current:
                    sequences.append(''.join(current))
                    current = []
            else:
                current.append(line)
    if current:
        sequences.append(''.join(current))
    return sequences


def expected_results(path):
    sequences = read_fasta(path)
    kmers = [''.join(chars) for chars in itertools.product('ACGT', repeat=3)]
    index = {kmer: i for i, kmer in enumerate(kmers)}
    matrix = np.zeros((len(sequences), 64), dtype=float)
    y = np.zeros(len(sequences), dtype=float)

    for row, sequence in enumerate(sequences):
        y[row] = sequence.count('G') + sequence.count('C')
        for pos in range(len(sequence) - 2):
            matrix[row, index[sequence[pos:pos + 3]]] += 1.0

    singular_values = np.linalg.svd(matrix, compute_uv=False)[:3]
    weights = np.linalg.solve(matrix.T @ matrix + np.eye(64), matrix.T @ y)
    return singular_values, float(weights.sum())


def remove_outputs():
    for path in (SVD_OUT, W_SUM_OUT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_submission():
    result = subprocess.run(
        [sys.executable, SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'analyze_kmers.py exited with status {result.returncode}. '
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )


def parse_outputs():
    assert os.path.isfile(SVD_OUT), f'{SVD_OUT} does not exist.'
    assert os.path.isfile(W_SUM_OUT), f'{W_SUM_OUT} does not exist.'

    with open(SVD_OUT, 'r') as handle:
        svd_content = handle.read().strip()
    with open(W_SUM_OUT, 'r') as handle:
        w_content = handle.read().strip()

    assert svd_content != '', f'{SVD_OUT} is empty.'
    assert w_content != '', f'{W_SUM_OUT} is empty.'

    try:
        svd_values = [float(value.strip()) for value in svd_content.split(',')]
    except ValueError:
        pytest.fail(f'Could not parse comma-separated floats from {SVD_OUT}. Content: {svd_content}')
    try:
        w_sum = float(w_content)
    except ValueError:
        pytest.fail(f'Could not parse float from {W_SUM_OUT}. Content: {w_content}')

    assert len(svd_values) == 3, f'Expected 3 singular values, got {len(svd_values)}.'
    return svd_values, w_sum


@pytest.fixture(scope='session', autouse=True)
def execute_original_input():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} script does not exist.'
    with open(FASTA, 'rb') as handle:
        fasta_before = handle.read()
    remove_outputs()
    run_submission()
    with open(FASTA, 'rb') as handle:
        assert handle.read() == fasta_before, 'The submission modified the input FASTA file.'


def test_analyze_kmers_script_exists():
    assert os.path.isfile(SCRIPT), '/home/user/analyze_kmers.py script does not exist.'


def test_svd_out_file():
    assert os.path.isfile(SVD_OUT), f'{SVD_OUT} does not exist.'
    with open(SVD_OUT, 'r') as f:
        content = f.read().strip()
    assert content != '', f'{SVD_OUT} is empty.'

    expected_values = [35.3115, 10.0354, 8.1209]
    try:
        actual_values = [float(x.strip()) for x in content.split(',')]
    except ValueError:
        pytest.fail(f'Could not parse comma-separated floats from {SVD_OUT}. Content: {content}')

    assert len(actual_values) == 3, f'Expected 3 singular values, got {len(actual_values)}.'
    for actual, expected in zip(actual_values, expected_values):
        assert abs(actual - expected) <= 1e-3, f'Singular value {actual} differs from expected {expected}.'


def test_w_sum_file():
    assert os.path.isfile(W_SUM_OUT), f'{W_SUM_OUT} does not exist.'
    with open(W_SUM_OUT, 'r') as f:
        content = f.read().strip()
    assert content != '', f'{W_SUM_OUT} is empty.'

    expected_w_sum = 0.2606
    try:
        actual_w_sum = float(content)
    except ValueError:
        pytest.fail(f'Could not parse float from {W_SUM_OUT}. Content: {content}')
    assert abs(actual_w_sum - expected_w_sum) <= 1e-3, f'w_sum {actual_w_sum} differs from expected {expected_w_sum}.'


def test_outputs_match_independent_computation():
    expected_svd, expected_w_sum = expected_results(FASTA)
    actual_svd, actual_w_sum = parse_outputs()
    for actual, expected in zip(actual_svd, expected_svd):
        assert abs(actual - expected) <= 1e-3
    assert abs(actual_w_sum - expected_w_sum) <= 1e-3


def test_script_on_unseen_fasta_input():
    with open(FASTA, 'rb') as handle:
        original_fasta = handle.read()

    rng = secrets.SystemRandom()
    sequences = [
        ''.join(rng.choice('ACGT') for _ in range(31 + i * 3))
        for i in range(8)
    ]
    replacement = ''.join(
        f'>verification_{i + 1}\n{sequence}\n'
        for i, sequence in enumerate(sequences)
    ).encode()

    try:
        with open(FASTA, 'wb') as handle:
            handle.write(replacement)
        expected_svd, expected_w_sum = expected_results(FASTA)
        remove_outputs()
        run_submission()
        with open(FASTA, 'rb') as handle:
            assert handle.read() == replacement, 'The submission modified the verification FASTA file.'
        actual_svd, actual_w_sum = parse_outputs()
        for actual, expected in zip(actual_svd, expected_svd):
            assert abs(actual - expected) <= 1e-3, f'Singular value {actual} differs from recomputed value {expected}.'
        assert abs(actual_w_sum - expected_w_sum) <= 1e-3, f'w_sum {actual_w_sum} differs from recomputed value {expected_w_sum}.'
    finally:
        with open(FASTA, 'wb') as handle:
            handle.write(original_fasta)
        remove_outputs()
        run_submission()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
