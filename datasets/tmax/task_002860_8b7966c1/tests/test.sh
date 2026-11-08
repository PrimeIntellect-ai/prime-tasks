#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest

BINARY = Path('/home/user/tokenize_bayes')
DATASET = Path('/home/user/dataset.txt')
OUTPUT = Path('/home/user/output.csv')


def test_compiled_binary_exists():
    assert BINARY.exists(), f'Compiled binary {BINARY} does not exist.'
    assert BINARY.is_file(), f'{BINARY} is not a file.'
    assert os.access(BINARY, os.X_OK), f'Compiled binary {BINARY} is not executable.'
    with BINARY.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{BINARY} is not a compiled ELF binary.'


def test_output_csv_correct():
    assert OUTPUT.exists(), f'Output file {OUTPUT} does not exist.'
    with OUTPUT.open('r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_rows = {
        'data,0.400000',
        'science,0.200000',
        'processing,0.200000',
        'mining,0.200000',
    }
    assert len(lines) == 5, f'Expected 5 nonempty lines in {OUTPUT}, but found {len(lines)}.'
    assert lines[0] == 'token,probability', 'CSV header is incorrect.'
    assert set(lines[1:]) == expected_rows, 'CSV token/probability rows are incorrect.'


def _expected_rows(counts):
    total = sum(counts.values())
    denominator = total + len(counts)  # BAYES_ALPHA=1.0
    return {f'{token},{(count + 1.0) / denominator:.6f}' for token, count in counts.items()}


def _run_case(counts):
    words = []
    # Interleave occurrences so a solution cannot rely on grouped input.
    remaining = dict(counts)
    while remaining:
        for token in list(remaining):
            words.append(token)
            remaining[token] -= 1
            if remaining[token] == 0:
                del remaining[token]

    DATASET.write_text(' '.join(words) + '\n')
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()

    env = os.environ.copy()
    env['BAYES_ALPHA'] = '1.0'
    result = subprocess.run(
        [str(BINARY)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=False
    )
    assert result.returncode == 0, (
        f'Binary exited with status {result.returncode}: '
        f'{result.stderr.decode(errors="replace")}'
    )
    assert OUTPUT.is_file(), 'Running the binary did not create output.csv.'

    raw_lines = OUTPUT.read_text().splitlines()
    assert raw_lines, 'Running the binary produced a blank output.csv.'
    assert raw_lines[0] == 'token,probability', 'Generated CSV header is incorrect.'
    assert len(raw_lines) == len(counts) + 1, 'Generated CSV has the wrong number of rows.'
    assert set(raw_lines[1:]) == _expected_rows(counts), (
        'Generated token/probability rows are incorrect.'
    )


def test_binary_processes_unseen_datasets():
    original_dataset = DATASET.read_bytes() if DATASET.exists() else None
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    try:
        nonce = secrets.token_hex(8)
        _run_case({
            f'alpha_{nonce}': 4,
            f'beta_{nonce}': 2,
            f'gamma_{nonce}': 1,
            f'delta_{nonce}': 3,
            f'epsilon_{nonce}': 1,
        })

        nonce = secrets.token_hex(8)
        _run_case({
            f'one_{nonce}': 1,
            f'two_{nonce}': 5,
            f'three_{nonce}': 2,
        })
    finally:
        if original_dataset is None:
            if DATASET.exists() or DATASET.is_symlink():
                DATASET.unlink()
        else:
            DATASET.write_bytes(original_dataset)

        if original_output is None:
            if OUTPUT.exists() or OUTPUT.is_symlink():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
