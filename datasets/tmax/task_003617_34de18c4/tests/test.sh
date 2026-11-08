#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import sys

import h5py
import numpy as np
import pytest
from scipy.stats import gaussian_kde


def test_venv_exists():
    """Verify that a real virtual environment was created."""
    venv_python = '/home/user/venv/bin/python'
    venv_config = '/home/user/venv/pyvenv.cfg'

    assert os.path.isfile(venv_python), f"Virtual environment python executable not found at {venv_python}"
    assert os.path.isfile(venv_config), f"Virtual environment configuration not found at {venv_config}"

    # A normal venv uses the trusted base Python executable via a symlink. This
    # rejects agent-controlled scripts or wrappers pretending to be Python.
    trusted_python = getattr(sys, '_base_executable', sys.executable)
    assert os.path.samefile(venv_python, trusted_python), \
        f"{venv_python} is not a real virtual-environment Python executable"

    # Keep the original package-import assertion.
    result = subprocess.run(
        [venv_python, '-c', 'import h5py, numpy, scipy'],
        capture_output=True,
    )
    assert result.returncode == 0, \
        "Required libraries (h5py, numpy, scipy) are not installed in the virtual environment."

    result = subprocess.run(
        [venv_python, '-c',
         'import json,sys; print(json.dumps({"prefix":sys.prefix,"base_prefix":sys.base_prefix}))'],
        capture_output=True,
        text=True,
        check=True,
    )
    info = json.loads(result.stdout.strip())
    assert os.path.realpath(info['prefix']) == os.path.realpath('/home/user/venv')
    assert os.path.realpath(info['base_prefix']) != os.path.realpath(info['prefix'])


def get_expected_values():
    """Compute expected values in the trusted verifier process."""
    with h5py.File('/home/user/input_data.h5', 'r') as f:
        mats = f['matrices'][:]

    conds = np.linalg.cond(mats)
    indices = np.where(conds >= 1e12)[0].tolist()
    log_conds = np.log10(conds)
    kde = gaussian_kde(log_conds)
    expected_kde = f"{kde(12.0)[0]:.4f}"
    return indices, expected_kde


def test_singular_indices():
    """Verify that singular_indices.txt contains the correct indices."""
    indices_file = '/home/user/singular_indices.txt'
    assert os.path.isfile(indices_file), f"Output file {indices_file} is missing."

    expected_indices, _ = get_expected_values()

    with open(indices_file, 'r') as f:
        lines = f.read().strip().split('\n')

    actual_indices = []
    for line in lines:
        if line.strip():
            try:
                actual_indices.append(int(line.strip()))
            except ValueError:
                pytest.fail(f"Found non-integer value in {indices_file}: '{line.strip()}'")

    assert actual_indices == expected_indices, \
        f"Expected indices {expected_indices}, but got {actual_indices}"


def test_kde_result():
    """Verify that kde_result.txt contains the correct KDE density value."""
    kde_file = '/home/user/kde_result.txt'
    assert os.path.isfile(kde_file), f"Output file {kde_file} is missing."

    _, expected_kde = get_expected_values()

    with open(kde_file, 'r') as f:
        actual_kde = f.read().strip()

    assert actual_kde == expected_kde, \
        f"Expected KDE value '{expected_kde}', but got '{actual_kde}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
