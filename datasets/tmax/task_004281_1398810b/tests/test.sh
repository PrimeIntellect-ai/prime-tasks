#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

PROJECT = Path('/home/user/project')
SOLVER = PROJECT / 'solver.py'
OUTPUT = PROJECT / 'output.txt'


@pytest.fixture(scope='session', autouse=True)
def run_submitted_solver():
    assert SOLVER.is_file(), '/home/user/project/solver.py does not exist.'
    assert not SOLVER.is_symlink(), 'solver.py must be a regular submitted file, not a symlink.'
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        [sys.executable, str(SOLVER)],
        cwd=str(PROJECT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'solver.py failed when executed. stdout={result.stdout!r}, stderr={result.stderr!r}'
    )


def test_output_file_exists():
    assert os.path.isfile('/home/user/project/output.txt'), "/home/user/project/output.txt does not exist. Did you run the script?"


def test_output_contents():
    with open('/home/user/project/output.txt', 'r') as f:
        content = f.read().strip().split('\n')

    assert len(content) == 2, "output.txt should contain exactly two lines."

    mean_line = content[0].strip()
    opt_line = content[1].strip()

    assert mean_line.startswith("Mean: "), "First line should start with 'Mean: '"
    assert opt_line.startswith("Opt: "), "Second line should start with 'Opt: '"

    try:
        mean_val = float(mean_line.split("Mean: ")[1])
    except ValueError:
        assert False, "Could not parse the mean value as a float."

    try:
        opt_val = float(opt_line.split("Opt: ")[1])
    except ValueError:
        assert False, "Could not parse the opt value as a float."

    # The true mean of 1..100 is 50.5
    # The minimum of x^2 - 50.5 * x is 25.25
    assert abs(mean_val - 50.5) < 1e-4, f"Calculated mean is incorrect. Expected ~50.5000, got {mean_val}"
    assert abs(opt_val - 25.25) < 1e-4, f"Optimized value is incorrect. Expected ~25.2500, got {opt_val}"


def test_output_formatting():
    with open('/home/user/project/output.txt', 'r') as f:
        content = f.read().strip().split('\n')

    assert len(content) == 2, "output.txt should contain exactly two lines."

    mean_match = re.match(r"^Mean: \d+\.\d{4}$", content[0].strip())
    assert mean_match is not None, "Mean output is not formatted to exactly 4 decimal places."

    opt_match = re.match(r"^Opt: \d+\.\d{4}$", content[1].strip())
    assert opt_match is not None, "Opt output is not formatted to exactly 4 decimal places."


def test_solver_parses_and_optimizes_unseen_binary_data():
    rng = random.Random(int.from_bytes(os.urandom(16), 'little'))

    for case in range(2):
        count = rng.randint(7, 43)
        values = [rng.randint(2, 800) / 4.0 for _ in range(count)]
        expected_mean = sum(values) / len(values)
        expected_opt = expected_mean / 2.0

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            shutil.copy2(SOLVER, tmp_path / 'solver.py')
            with open(tmp_path / 'data.bin', 'wb') as f:
                f.write(b'DATA')
                f.write(struct.pack('<I', count))
                for value in values:
                    f.write(struct.pack('<d', value))

            result = subprocess.run(
                [sys.executable, 'solver.py'],
                cwd=tmp,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert result.returncode == 0, (
                f'solver.py failed on unseen case {case}: '
                f'stdout={result.stdout!r}, stderr={result.stderr!r}'
            )

            generated = tmp_path / 'output.txt'
            assert generated.is_file(), 'solver.py did not generate output.txt when executed.'
            lines = generated.read_text().strip().split('\n')
            assert len(lines) == 2, 'Generated output.txt should contain exactly two lines.'
            assert re.fullmatch(r'Mean: -?\d+\.\d{4}', lines[0].strip())
            assert re.fullmatch(r'Opt: -?\d+\.\d{4}', lines[1].strip())

            actual_mean = float(lines[0].split('Mean: ', 1)[1])
            actual_opt = float(lines[1].split('Opt: ', 1)[1])
            assert abs(actual_mean - expected_mean) < 1.1e-4, (
                f'Incorrect mean for unseen binary data: expected {expected_mean}, got {actual_mean}'
            )
            assert abs(actual_opt - expected_opt) < 1.1e-4, (
                f'Incorrect optimum for unseen binary data: expected {expected_opt}, got {actual_opt}'
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
