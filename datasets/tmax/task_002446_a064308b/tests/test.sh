#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest


def test_makefile_rebuilds_working_extension():
    makefile = '/app/spectrosim/Makefile'
    assert os.path.isfile(makefile), f"Missing Makefile: {makefile}"

    for path in glob.glob('/app/spectrosim/_spectrosim*.so'):
        os.remove(path)

    result = subprocess.run(
        ['make', '-C', '/app/spectrosim'],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"Fresh build using the repaired Makefile failed:\n{result.stdout}"

    env = os.environ.copy()
    env['PYTHONPATH'] = '/app/spectrosim:/app'
    result = subprocess.run(
        [sys.executable, '-c', 'import spectrosim; print(spectrosim.simulate([1.0], 1.0, 1.0, 1.0, 0.0, 2.0, 1.0))'],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f"Freshly built extension cannot be imported or used:\n{result.stdout}"


def test_fit_script_exists_and_runs():
    script_path = '/home/user/fit_spectrum.py'
    solution_path = '/home/user/solution.json'
    assert os.path.isfile(script_path), f"Missing fitting script: {script_path}"

    if os.path.exists(solution_path):
        os.remove(solution_path)

    env = os.environ.copy()
    env['PYTHONPATH'] = '/app/spectrosim:/app'
    result = subprocess.run(
        [sys.executable, script_path],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f"Fitting script failed:\n{result.stdout}"
    assert os.path.isfile(solution_path), "Fitting script did not create /home/user/solution.json"


def test_solution_json_exists_and_valid():
    solution_path = '/home/user/solution.json'
    assert os.path.isfile(solution_path), f"Missing solution file: {solution_path}"

    with open(solution_path, 'r') as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {solution_path} is not a valid JSON.")

    expected_keys = {"A1", "mu1", "sigma1", "A2", "mu2", "sigma2"}
    assert set(params.keys()) == expected_keys, f"JSON must contain exactly these keys: {expected_keys}"

    for k in expected_keys:
        assert isinstance(params[k], (int, float)), f"Parameter {k} must be a number."


def test_spectrosim_importable():
    sys.path.append('/app/spectrosim')
    try:
        import spectrosim
    except ImportError as e:
        pytest.fail(f"Failed to import spectrosim. Did you fix the Makefile and compile the package? Error: {e}")


def test_mse_metric():
    solution_path = '/home/user/solution.json'
    data_path = '/home/user/data/spectrum.csv'

    assert os.path.isfile(solution_path), f"Missing solution file: {solution_path}"
    assert os.path.isfile(data_path), f"Missing data file: {data_path}"

    with open(solution_path, 'r') as f:
        params = json.load(f)

    df = pd.read_csv(data_path)
    x = df['wavelength'].values
    y_true = df['intensity'].values

    sys.path.append('/app/spectrosim')
    import spectrosim

    y_sim = spectrosim.simulate(
        x,
        params['A1'], params['mu1'], params['sigma1'],
        params['A2'], params['mu2'], params['sigma2']
    )

    mse = np.mean((y_true - y_sim)**2)
    threshold = 1e-4

    assert mse <= threshold, f"MSE is {mse}, which is greater than the threshold {threshold}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
