#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def exact_B(k1, k2, t):
    t = np.asarray(t, dtype=float)
    if np.isclose(k1, k2):
        return k1 * t * np.exp(-k1 * t)
    return (k1 / (k2 - k1)) * (np.exp(-k1 * t) - np.exp(-k2 * t))


def check_simulator_in_subprocess(source_path=None):
    if source_path is None:
        loader = "from bio_kinetics import simulate_B"
    else:
        loader = f"""
import importlib.util
spec = importlib.util.spec_from_file_location('submitted_solver', {source_path!r})
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
simulate_B = module.simulate_B
"""

    code = loader + r'''
import numpy as np

def exact(k1, k2, t):
    if np.isclose(k1, k2):
        return k1 * t * np.exp(-k1 * t)
    return (k1 / (k2-k1)) * (np.exp(-k1*t) - np.exp(-k2*t))

cases = [
    (3.4, 0.37, np.linspace(0.0, 8.0, 81)),
    (0.42, 2.6, np.linspace(0.0, 10.0, 67)),
    (1.15, 1.15, np.linspace(0.0, 6.0, 61)),
]
for k1, k2, t in cases:
    got = np.asarray(simulate_B(k1, k2, t), dtype=float)
    assert got.shape == t.shape
    assert np.all(np.isfinite(got))
    assert np.max(np.abs(got - exact(k1, k2, t))) < 0.003
print('ok')
'''
    env = os.environ.copy()
    env.pop('PYTHONPATH', None)
    result = subprocess.run(
        [sys.executable, '-c', code],
        cwd='/tmp', env=env, text=True, capture_output=True, timeout=8
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'ok' in result.stdout


def contains_pair_of_ones(node):
    if isinstance(node, (ast.List, ast.Tuple)) and len(node.elts) == 2:
        return all(isinstance(x, ast.Constant) and isinstance(x.value, (int, float)) and float(x.value) == 1.0 for x in node.elts)
    if isinstance(node, ast.Call) and node.args:
        return contains_pair_of_ones(node.args[0])
    return False


def script_uses_required_initial_guess(source):
    tree = ast.parse(source)
    assigned = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assigned[target.id] = node.value

    for name, value in assigned.items():
        if re.search(r'(initial|guess|x0|p0|start)', name, re.I) and contains_pair_of_ones(value):
            return True

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            for keyword in node.keywords:
                if keyword.arg in ('p0', 'x0'):
                    value = keyword.value
                    if contains_pair_of_ones(value):
                        return True
                    if isinstance(value, ast.Name) and contains_pair_of_ones(assigned.get(value.id)):
                        return True
    return False


def find_fitting_script():
    candidates = []
    for path in Path('/home/user').rglob('*.py'):
        if not path.is_file():
            continue
        source = path.read_text(errors='replace')
        if 'spectroscopy.csv' not in source or 'fitted_params.csv' not in source:
            continue
        score = 0
        score += 4 if 'bio_kinetics' in source else 0
        score += 4 if 'simulate_B' in source else 0
        score += 2 if re.search(r'curve_fit|least_squares|minimize|optimi[sz]|fit', source, re.I) else 0
        score += 2 if script_uses_required_initial_guess(source) else 0
        candidates.append((score, str(path), source))

    assert candidates, "No Python fitting script reading spectroscopy.csv and writing fitted_params.csv was found under /home/user."
    candidates.sort(key=lambda item: (-item[0], item[1]))
    score, path, source = candidates[0]
    assert 'bio_kinetics' in source and 'simulate_B' in source, "The fitting script must use bio_kinetics.simulate_B."
    assert script_uses_required_initial_guess(source), "The fitting script must use the required initial guess k1=1.0, k2=1.0."
    return path


def run_script(path):
    env = os.environ.copy()
    result = subprocess.run(
        [sys.executable, path], cwd=os.path.dirname(path) or '/home/user',
        env=env, text=True, capture_output=True, timeout=75
    )
    assert result.returncode == 0, f"Fitting script failed:\n{result.stdout}\n{result.stderr}"


def read_params():
    params_file = '/home/user/fitted_params.csv'
    assert os.path.exists(params_file), f"Error: {params_file} not found."

    with open(params_file, 'r') as f:
        raw = f.read()
    line = raw.strip()
    assert '\n' not in line and '\r' not in line, f"Expected exactly one line in {params_file}, but got: {raw!r}"

    parts = line.split(',')
    assert len(parts) == 2, f"Expected exactly two comma-separated values in {params_file}, but got: {line}"

    try:
        k1, k2 = float(parts[0]), float(parts[1])
    except ValueError:
        assert False, f"Could not parse k1 and k2 as floats from: {line}"
    assert np.isfinite(k1) and np.isfinite(k2), "Fitted parameters must be finite."
    return k1, k2


def assert_original_mse():
    k1, k2 = read_params()

    data_file = '/home/user/data/spectroscopy.csv'
    assert os.path.exists(data_file), f"Data file {data_file} is missing."

    data = pd.read_csv(data_file)
    assert 'time' in data.columns and 'signal' in data.columns, "Data file must contain 'time' and 'signal' columns."

    t_data = data['time'].values
    signal_data = data['signal'].values
    predicted_signal = exact_B(k1, k2, t_data)
    mse = np.mean((predicted_signal - signal_data) ** 2)

    threshold = 0.005
    assert mse < threshold, f"MSE is {mse:.6f}, which is not less than the threshold {threshold}. Fitted parameters: k1={k1}, k2={k2}"


def test_complete_submission():
    source_solver = '/app/bio_kinetics/bio_kinetics/solver.py'
    assert os.path.isfile(source_solver), "The bio_kinetics solver source is missing."

    try:
        dist = importlib.metadata.distribution('bio_kinetics')
    except importlib.metadata.PackageNotFoundError:
        assert False, "bio_kinetics is not installed in the Python environment."
    assert dist.version, "Installed bio_kinetics distribution has no version."

    # Exercise both the repaired source tree and the installed package. The timeout
    # also detects the original inverted adaptation rule, which repeatedly rejects
    # steps without making progress.
    check_simulator_in_subprocess(source_solver)
    check_simulator_in_subprocess()

    script = find_fitting_script()
    data_file = Path('/home/user/data/spectroscopy.csv')
    original_data = data_file.read_bytes()

    # Execute the submitted artifact rather than trusting a prewritten CSV.
    run_script(script)
    assert_original_mse()

    # Exercise the fitter on a second, verifier-derived data set so fixed or guessed
    # parameters for the public data cannot satisfy the script requirement.
    t = np.linspace(0.0, 5.0, 26)
    synthetic = pd.DataFrame({'time': t, 'signal': exact_B(0.55, 1.65, t)})
    try:
        synthetic.to_csv(data_file, index=False)
        params_path = Path('/home/user/fitted_params.csv')
        if params_path.exists():
            params_path.unlink()
        run_script(script)
        k1, k2 = read_params()
        mse = np.mean((exact_B(k1, k2, t) - synthetic['signal'].to_numpy()) ** 2)
        assert mse < 0.0005, f"The fitting script did not fit a changed valid data set; MSE={mse:.6f}."
    finally:
        data_file.write_bytes(original_data)

    # Leave and verify the requested result for the original experimental data.
    run_script(script)
    assert_original_mse()
TEST_EOF

if timeout 210s python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
