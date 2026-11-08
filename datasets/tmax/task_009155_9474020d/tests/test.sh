#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

HOME = Path('/home/user')
DATASET = HOME / 'dataset.csv'
RANK_FILE = HOME / 'rank.txt'
MSE_FILE = HOME / 'mse.txt'


def test_rank_file_exists_and_correct():
    """Test that rank.txt exists and contains the correct rank (15)."""
    rank_path = '/home/user/rank.txt'
    assert os.path.exists(rank_path), f'File not found: {rank_path}'
    assert os.path.isfile(rank_path), f'Path is not a file: {rank_path}'

    with open(rank_path, 'r') as f:
        content = f.read().strip()

    assert content == '15', f"Incorrect rank. Expected '15', got '{content}'"


def test_mse_file_exists_and_small():
    """Test that mse.txt exists and contains a very small floating point number."""
    mse_path = '/home/user/mse.txt'
    assert os.path.exists(mse_path), f'File not found: {mse_path}'
    assert os.path.isfile(mse_path), f'Path is not a file: {mse_path}'

    with open(mse_path, 'r') as f:
        content = f.read().strip()

    try:
        mse_value = float(content)
    except ValueError:
        pytest.fail(f"Content of mse.txt is not a valid float: '{content}'")

    assert mse_value < 1e-20, f'MSE is too large: {mse_value}. Expected a value < 1e-20.'
    assert mse_value >= 0.0, f'MSE cannot be negative: {mse_value}.'


def _reference_values(x):
    rank = int(np.linalg.matrix_rank(x))
    u, s, vt = np.linalg.svd(x, full_matrices=False)
    reconstructed = (u[:, :rank] * s[:rank]) @ vt[:rank, :]
    mse = float(np.mean((x - reconstructed) ** 2))
    assert mse > 0.0 and np.isfinite(mse)
    return rank, mse


def _candidate_scripts():
    scripts = []
    for path in HOME.rglob('*.py'):
        if not path.is_file() or path.is_symlink():
            continue
        if any(part in {'.local', '__pycache__', 'site-packages'} for part in path.parts):
            continue
        scripts.append(path)
    return sorted(scripts)


def _run_as_user(script):
    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        [sys.executable, str(script)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        preexec_fn=demote,
    )


def _exercise(script, trials):
    for index, x in enumerate(trials):
        np.savetxt(DATASET, x, delimiter=',')
        RANK_FILE.unlink(missing_ok=True)
        MSE_FILE.unlink(missing_ok=True)

        result = _run_as_user(script)
        if result.returncode != 0:
            return f'trial {index}: exited {result.returncode}: {result.stderr[-500:]}'
        if not RANK_FILE.is_file() or not MSE_FILE.is_file():
            return f'trial {index}: did not create both output files'

        expected_rank, expected_mse = _reference_values(x)
        rank_text = RANK_FILE.read_text().strip()
        if rank_text != str(expected_rank):
            return f"trial {index}: expected rank {expected_rank}, got '{rank_text}'"

        try:
            reported_mse = float(MSE_FILE.read_text().strip())
        except ValueError:
            return f'trial {index}: mse.txt is not a float'

        if not np.isfinite(reported_mse) or reported_mse < 0.0 or reported_mse >= 1e-20:
            return f'trial {index}: invalid or insufficiently small MSE {reported_mse}'
        if reported_mse == 0.0:
            return f'trial {index}: reported zero instead of the measured floating-point error'

        ratio = reported_mse / expected_mse
        if not (1e-3 <= ratio <= 1e3):
            return (
                f'trial {index}: reported MSE {reported_mse} is inconsistent with '
                f'independently reconstructed MSE {expected_mse}'
            )
    return None


def test_python_solution_recomputes_rank_and_reconstruction_error():
    scripts = _candidate_scripts()
    assert scripts, 'No Python solution script was found under /home/user'

    original_dataset = DATASET.read_bytes()
    original_rank = RANK_FILE.read_bytes()
    original_mse = MSE_FILE.read_bytes()

    original_x = np.loadtxt(DATASET, delimiter=',')
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), 'big'))
    r1 = int(rng.integers(4, 9))
    r2 = int(rng.integers(10, 15))
    x1 = rng.standard_normal((137, r1)) @ rng.standard_normal((r1, 29))
    x2 = 1e4 * (rng.standard_normal((173, r2)) @ rng.standard_normal((r2, 31)))
    trials = [original_x, x1, x2]

    failures = []
    try:
        for script in scripts:
            try:
                failure = _exercise(script, trials)
            except (subprocess.TimeoutExpired, OSError, Exception) as exc:
                failure = f'{type(exc).__name__}: {exc}'
            if failure is None:
                return
            failures.append(f'{script}: {failure}')
    finally:
        DATASET.write_bytes(original_dataset)
        RANK_FILE.write_bytes(original_rank)
        MSE_FILE.write_bytes(original_mse)

    pytest.fail('No solution script passed derived-input checks:\n' + '\n'.join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
