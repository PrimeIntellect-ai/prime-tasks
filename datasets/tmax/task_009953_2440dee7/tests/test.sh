#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import math
import os
from pathlib import Path
import random
import re
import subprocess

import pytest

RESULTS = Path('/home/user/svd_results.txt')
PROJECT = Path('/home/user/bio_svd')
FASTA = Path('/home/user/data/seqs.fasta')


def read_result_lines():
    with RESULTS.open('r') as f:
        return [line.strip() for line in f if line.strip()]


def assert_result_file(expected):
    assert RESULTS.exists(), f'File {RESULTS} does not exist. Did you run your Rust program?'
    assert RESULTS.is_file(), f'Path {RESULTS} is not a file.'
    lines = read_result_lines()
    assert len(lines) == 3, f'Expected exactly 3 lines in {RESULTS}, found {len(lines)}.'

    for i, (actual_str, expected_value) in enumerate(zip(lines, expected)):
        try:
            actual = float(actual_str)
        except ValueError:
            pytest.fail(f"Line {i+1} in {RESULTS} is not a valid float: '{actual_str}'")

        assert math.isclose(actual, expected_value, abs_tol=1e-4), \
            f'Value on line {i+1} is incorrect. Expected {expected_value:.4f}, got {actual:.4f}.'

        parts = actual_str.split('.')
        if len(parts) == 2:
            assert len(parts[1]) == 4, \
                f"Value '{actual_str}' on line {i+1} is not formatted to exactly 4 decimal places."
        else:
            pytest.fail(
                f"Value '{actual_str}' on line {i+1} is not formatted to exactly 4 decimal places."
            )


def singular_values_from_sequences(sequences):
    kmers = [''.join(chars) for chars in itertools.product('ACGT', repeat=3)]
    index = {kmer: i for i, kmer in enumerate(kmers)}
    matrix = []
    for sequence in sequences:
        row = [0.0] * 64
        for i in range(len(sequence) - 2):
            row[index[sequence[i:i + 3]]] += 1.0
        matrix.append(row)

    n = len(matrix)
    gram = [[sum(matrix[i][k] * matrix[j][k] for k in range(64))
             for j in range(n)] for i in range(n)]

    # Jacobi eigenvalue algorithm for the small symmetric Gram matrix M*M^T.
    for _ in range(10000):
        p, q = 0, 1
        largest = 0.0
        for i in range(n):
            for j in range(i + 1, n):
                if abs(gram[i][j]) > largest:
                    largest = abs(gram[i][j])
                    p, q = i, j
        if largest < 1e-12:
            break

        app, aqq, apq = gram[p][p], gram[q][q], gram[p][q]
        tau = (aqq - app) / (2.0 * apq)
        t = (1.0 if tau >= 0.0 else -1.0) / (abs(tau) + math.sqrt(1.0 + tau * tau))
        c = 1.0 / math.sqrt(1.0 + t * t)
        s = t * c

        for k in range(n):
            if k == p or k == q:
                continue
            akp, akq = gram[k][p], gram[k][q]
            gram[k][p] = gram[p][k] = c * akp - s * akq
            gram[k][q] = gram[q][k] = s * akp + c * akq

        gram[p][p] = c * c * app - 2.0 * s * c * apq + s * s * aqq
        gram[q][q] = s * s * app + 2.0 * s * c * apq + c * c * aqq
        gram[p][q] = gram[q][p] = 0.0
    else:
        pytest.fail('Verifier eigenvalue calculation did not converge')

    eigenvalues = sorted((max(0.0, gram[i][i]) for i in range(n)), reverse=True)
    return [math.sqrt(value) for value in eigenvalues[:3]]


def test_01_original_svd_results_file_exists():
    assert RESULTS.exists(), f'File {RESULTS} does not exist. Did you run your Rust program?'
    assert RESULTS.is_file(), f'Path {RESULTS} is not a file.'


def test_02_original_svd_results_content():
    assert_result_file([11.6669, 2.2858, 2.0729])


def test_03_rust_nalgebra_project_exists():
    manifest = PROJECT / 'Cargo.toml'
    main_source = PROJECT / 'src' / 'main.rs'
    assert PROJECT.is_dir(), f'{PROJECT} is not a directory.'
    assert manifest.is_file(), f'{manifest} does not exist.'
    assert main_source.is_file(), f'{main_source} does not exist.'

    completed = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1',
         '--manifest-path', str(manifest)],
        cwd=str(PROJECT), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=60
    )
    assert completed.returncode == 0, f'Invalid Cargo project:\n{completed.stderr}'
    metadata = json.loads(completed.stdout)
    manifest_real = manifest.resolve()
    packages = [p for p in metadata.get('packages', [])
                if Path(p['manifest_path']).resolve() == manifest_real]
    assert packages, 'Cargo metadata does not contain the requested project.'
    assert any('bin' in target.get('kind', []) for p in packages for target in p.get('targets', [])), \
        'The Cargo project does not define a Rust executable target.'
    assert any(dep.get('name') == 'nalgebra' for p in packages for dep in p.get('dependencies', [])), \
        'Cargo.toml must declare the nalgebra crate as a dependency.'

    rust_sources = list(PROJECT.rglob('*.rs'))
    source_text = '\n'.join(path.read_text(errors='replace') for path in rust_sources)
    assert re.search(r'\bnalgebra\b', source_text), \
        'The Rust source does not use the nalgebra crate.'


def test_04_program_recomputes_results_from_fasta():
    original_fasta = FASTA.read_bytes()
    original_results = RESULTS.read_bytes() if RESULTS.exists() else None

    rng = random.SystemRandom()
    sequences = []
    for i in range(7):
        # Different lengths and random content exercise overlapping 3-mer counting
        # without exposing fixed answers that can be copied into the program.
        sequences.append(''.join(rng.choice('ACGT') for _ in range(19 + i)))

    expected = singular_values_from_sequences(sequences)
    replacement = ''.join(f'>verification_{i}\n{sequence}\n'
                          for i, sequence in enumerate(sequences))

    try:
        FASTA.write_text(replacement)
        if RESULTS.exists():
            RESULTS.unlink()

        completed = subprocess.run(
            ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
            cwd=str(PROJECT), text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=180
        )
        assert completed.returncode == 0, \
            f'The Rust program failed on a valid FASTA input:\n{completed.stderr}'
        assert RESULTS.exists() and RESULTS.is_file(), \
            'Running the Rust program did not recreate /home/user/svd_results.txt.'
        assert_result_file(expected)
    finally:
        FASTA.write_bytes(original_fasta)
        if original_results is None:
            if RESULTS.exists():
                RESULTS.unlink()
        else:
            RESULTS.write_bytes(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
