#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

import h5py
import numpy as np
import pytest

SOURCE = Path('/home/user/preprocess.c')
FASTA = Path('/home/user/raw_sequences.fasta')
OUTPUT = Path('/home/user/cleaned_data.h5')
EXECUTABLE = Path('/tmp/preprocess_verifier')


@pytest.fixture(scope='session')
def compiled_program():
    assert SOURCE.exists(), f'C source file {SOURCE} is missing.'
    assert SOURCE.is_file(), f'Path {SOURCE} is not a regular file.'

    result = subprocess.run(
        ['h5cc', str(SOURCE), '-o', str(EXECUTABLE)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'Failed to compile {SOURCE} with h5cc.\n'
        f'STDOUT: {result.stdout}\nSTDERR: {result.stderr}'
    )
    assert EXECUTABLE.is_file(), 'Compilation did not produce an executable.'
    return EXECUTABLE


def run_program(executable):
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    result = subprocess.run(
        [str(executable)],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'Compiled program failed.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}'
    )
    assert OUTPUT.exists(), f'Compiled program did not create {OUTPUT}.'
    assert OUTPUT.is_file(), f'Path {OUTPUT} is not a file.'


def numeric_rows(sequences):
    mapping = {'A': 1.0, 'C': 2.0, 'G': 3.0, 'T': 4.0}
    return np.array(
        [[mapping[base.upper()] for base in sequence] for sequence in sequences],
        dtype=np.float64,
    )


def test_compiled_c_program_generates_output(compiled_program):
    original_fasta = FASTA.read_bytes()
    alphabet = 'ACGT'
    unique = []
    while len(unique) < 5:
        candidate = ''.join(secrets.choice(alphabet) for _ in range(17))
        if candidate not in unique:
            unique.append(candidate)

    records = [
        unique[0], unique[1].lower(), unique[0].lower(), unique[2],
        unique[3], unique[1].upper(), unique[4], unique[2].lower(),
    ]
    randomized_fasta = ''.join(
        f'>record_{index}\n{sequence}\n'
        for index, sequence in enumerate(records)
    )
    expected = numeric_rows(unique)

    try:
        FASTA.write_text(randomized_fasta)
        run_program(compiled_program)

        with h5py.File(OUTPUT, 'r') as handle:
            assert '/unique_matrix' in handle, "Dataset '/unique_matrix' not found."
            dataset = handle['/unique_matrix']
            data = dataset[:]
            assert dataset.dtype == np.dtype(np.float64), (
                f'Expected a double dataset, got {dataset.dtype}.'
            )
            assert data.shape == expected.shape, (
                f'Expected randomized shape {expected.shape}, got {data.shape}.'
            )
            assert np.array_equal(data, expected), (
                'Program did not correctly map and deduplicate randomized FASTA rows.'
            )
    finally:
        FASTA.write_bytes(original_fasta)
        run_program(compiled_program)


def test_cleaned_data_exists():
    """Test that the cleaned_data.h5 file was created."""
    file_path = '/home/user/cleaned_data.h5'
    assert os.path.exists(file_path), f'Output file {file_path} is missing.'
    assert os.path.isfile(file_path), f'Path {file_path} is not a file.'


def test_hdf5_content():
    """Test that the HDF5 file contains the correct deduplicated matrix."""
    script = r'''
import h5py
import numpy as np
import sys

try:
    with h5py.File('/home/user/cleaned_data.h5', 'r') as f:
        if '/unique_matrix' not in f:
            print("Dataset '/unique_matrix' not found.")
            sys.exit(1)

        data = f['/unique_matrix'][:]

        expected = np.array([
            [1., 2., 3., 4., 1., 2., 3., 4., 1., 2., 3., 4.],
            [2., 2., 2., 2., 3., 3., 3., 3., 4., 4., 4., 4.],
            [1., 4., 1., 4., 1., 4., 1., 4., 1., 4., 1., 4.],
            [4., 4., 4., 4., 4., 4., 4., 4., 4., 4., 4., 4.]
        ], dtype=np.float64)

        if data.shape != expected.shape:
            print(f"Expected shape {expected.shape}, got {data.shape}")
            sys.exit(1)

        if not np.allclose(data, expected):
            print('Matrix values do not match expected deduplicated values.')
            sys.exit(1)

except Exception as e:
    print(f'Exception: {e}')
    sys.exit(1)

sys.exit(0)
'''
    result = subprocess.run(
        ['python3', '-c', script],
        capture_output=True,
        text=True,
    )

    error_msg = (
        f'HDF5 validation failed.\nSTDOUT: {result.stdout.strip()}\n'
        f'STDERR: {result.stderr.strip()}'
    )
    assert result.returncode == 0, error_msg
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
