#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
INPUT = HOME / 'input.fasta'
SOURCE = HOME / 'simulate.cpp'
BINARY = HOME / 'simulate'
OUTPUT = HOME / 'output.csv'
NOTEBOOK = HOME / 'analyze.ipynb'
LOG = HOME / 'max_concentration.log'


def compute_expected_max():
    S_map = {'A': 1.0, 'T': 0.8, 'C': 0.5, 'G': 0.2}
    sequences = [
        "ATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGAT",
        "AAAAATTTTTCCCCCGGGGGAAAAATTTTTCCCCCGGGGGAAAAATTTTT",
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG",
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTAC",
        "TCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTCTC"
    ]

    D = 0.5
    dx = 1.0
    dt = 0.1
    koff = 0.01
    kon = 0.05
    steps = 100
    L = 50
    max_val = 0.0

    for seq in sequences:
        u = [0.0] * L
        S = [S_map.get(base, 0.0) for base in seq]
        for _ in range(steps):
            new_u = list(u)
            for i in range(1, L - 1):
                diffusion = D * (u[i-1] - 2*u[i] + u[i+1]) / (dx * dx)
                reaction = -koff * u[i] + kon * S[i]
                new_u[i] = u[i] + dt * (diffusion + reaction)
            u = new_u
        for val in u:
            if val > max_val:
                max_val = val

    return f"Max Concentration: {max_val:.4f}"


def parse_fasta(text):
    sequences = []
    current = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith('>'):
            if current:
                sequences.append(''.join(current).upper())
                current = []
        else:
            current.append(line)
    if current:
        sequences.append(''.join(current).upper())
    return sequences


def expected_grid(sequences):
    assert len(sequences) == 5
    affinity = {'A': 1.0, 'T': 0.8, 'C': 0.5, 'G': 0.2}
    u = [[0.0] * 50 for _ in range(5)]
    for _ in range(100):
        new_u = [row[:] for row in u]
        for s in range(5):
            assert len(sequences[s]) >= 50
            for i in range(1, 49):
                diffusion = 0.5 * (u[s][i-1] - 2.0*u[s][i] + u[s][i+1])
                reaction = -0.01*u[s][i] + 0.05*affinity[sequences[s][i]]
                new_u[s][i] = u[s][i] + 0.1*(diffusion + reaction)
            new_u[s][0] = 0.0
            new_u[s][49] = 0.0
        u = new_u
    return u


def read_and_check_csv(expected):
    assert OUTPUT.is_file(), '/home/user/output.csv was not generated.'
    lines = OUTPUT.read_text().splitlines()
    assert len(lines) == 5, f'output.csv must have 5 rows, got {len(lines)}.'
    rows = list(csv.reader(lines))
    assert all(len(row) == 50 for row in rows), 'Every output.csv row must have 50 columns.'
    pattern = re.compile(r'^-?\d+\.\d{4}$')
    for s, row in enumerate(rows):
        for i, token in enumerate(row):
            assert pattern.fullmatch(token), f'CSV value {token!r} is not formatted to 4 decimal places.'
            expected_token = f'{expected[s][i]:.4f}'
            assert token == expected_token, (
                f'Incorrect concentration at row {s+1}, column {i+1}: '
                f'expected {expected_token}, got {token}.'
            )


def compile_simulator():
    result = subprocess.run(
        ['g++', '-std=c++17', '-O2', str(SOURCE), '-o', str(BINARY)],
        cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=120
    )
    assert result.returncode == 0, f'simulate.cpp did not compile:\n{result.stdout}'
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)


def run_simulator(sequences):
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        [str(BINARY)], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert result.returncode == 0, f'Simulator failed:\n{result.stdout}'
    expected = expected_grid(sequences)
    read_and_check_csv(expected)
    return expected


def execute_notebook():
    if LOG.exists():
        LOG.unlink()
    result = subprocess.run(
        ['jupyter', 'nbconvert', '--to', 'notebook', '--execute', '--inplace',
         '--ExecutePreprocessor.timeout=120', str(NOTEBOOK)],
        cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=180
    )
    assert result.returncode == 0, f'analyze.ipynb did not execute successfully:\n{result.stdout}'
    assert LOG.is_file(), 'Executing analyze.ipynb did not generate max_concentration.log.'


def test_files_exist():
    assert os.path.exists('/home/user/simulate.cpp'), '/home/user/simulate.cpp is missing.'
    assert os.path.exists('/home/user/analyze.ipynb'), '/home/user/analyze.ipynb is missing.'
    assert os.path.exists('/home/user/output.csv'), '/home/user/output.csv is missing.'
    assert os.path.exists('/home/user/max_concentration.log'), '/home/user/max_concentration.log is missing.'


def test_max_concentration_log():
    log_path = '/home/user/max_concentration.log'
    assert os.path.exists(log_path), f'{log_path} is missing.'
    with open(log_path, 'r') as f:
        content = f.read().strip()
    expected_content = compute_expected_max()
    assert content == expected_content, (
        f"Content of {log_path} is incorrect. Expected '{expected_content}', got '{content}'."
    )


def test_artifacts_execute_and_compute_results():
    assert SOURCE.is_file() and SOURCE.stat().st_size > 0, 'simulate.cpp must be a nonempty file.'
    assert NOTEBOOK.is_file() and NOTEBOOK.stat().st_size > 0, 'analyze.ipynb must be a nonempty file.'

    original_input = INPUT.read_bytes()
    original_sequences = parse_fasta(original_input.decode())
    compile_simulator()

    try:
        # Check the supplied data set.
        original_expected = run_simulator(original_sequences)
        execute_notebook()
        expected_log = f'Max Concentration: {max(map(max, original_expected)):.4f}'
        assert LOG.read_text().strip() == expected_log
        read_and_check_csv(original_expected)

        # Exercise the compiled source on an unpredictable valid FASTA input so
        # a hardcoded CSV for the supplied sequences cannot pass.
        rng = secrets.SystemRandom()
        random_sequences = [
            ''.join(rng.choice('ATCG') for _ in range(50)) for _ in range(5)
        ]
        random_fasta = ''.join(
            f'>test{i+1}\n{seq}\n' for i, seq in enumerate(random_sequences)
        )
        INPUT.write_text(random_fasta)
        run_simulator(random_sequences)

        # Independently prove that the notebook reads output.csv and computes
        # its maximum rather than merely writing the known simulation answer.
        probe = [['0.1234'] * 50 for _ in range(5)]
        probe[0][0] = '9.8765'
        OUTPUT.write_text('\n'.join(','.join(row) for row in probe) + '\n')
        execute_notebook()
        assert LOG.read_text().strip() == 'Max Concentration: 9.8765', (
            'The notebook did not derive the maximum from output.csv.'
        )
    finally:
        INPUT.write_bytes(original_input)

    # Leave and verify the requested final artifacts for the original input.
    final_expected = run_simulator(original_sequences)
    execute_notebook()
    expected_log = f'Max Concentration: {max(map(max, final_expected)):.4f}'
    assert LOG.read_text().strip() == expected_log
    read_and_check_csv(final_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
