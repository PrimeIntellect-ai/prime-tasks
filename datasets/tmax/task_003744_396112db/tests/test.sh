#!/bin/bash
set -e
mkdir -p /logs/verifier

# Remove any stale answer and execute the required wrapper.
rm -f /home/user/solution.txt
run_ok=0
if /home/user/run.sh; then
    run_ok=1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess


def test_run_sh_exists_and_executable():
    path = '/home/user/run.sh'
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."


def test_analyze_py_exists():
    path = '/home/user/analyze.py'
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."


def reference_solution():
    python = '/home/user/venv/bin/python'
    assert os.path.isfile(python), "The required virtual environment was not created."

    code = r'''
import numpy as np
import pandas as pd
from scipy.optimize import minimize

values = pd.read_csv('/home/user/sim_data.csv')[['x', 'y']].to_numpy(dtype=float)
mu = values.mean(axis=0)
cov_reg = np.cov(values, rowvar=False) + 1e-4 * np.eye(2)
precision = np.linalg.inv(cov_reg)

# The normalizing constant is irrelevant to the minimizer.
def objective(z):
    delta = z - mu
    return 0.5 * delta @ precision @ delta + np.sin(z[0]) + np.cos(z[1])

def gradient(z):
    delta = z - mu
    return precision @ delta + np.array([np.cos(z[0]), -np.sin(z[1])])

result = minimize(objective, mu, jac=gradient, method='BFGS')
if not np.all(np.isfinite(result.x)):
    raise RuntimeError('Reference optimization did not produce finite coordinates')
print(f'{result.x[0]:.12f},{result.x[1]:.12f}')
'''
    output = subprocess.check_output([python, '-c', code], text=True).strip()
    x_text, y_text = output.split(',')
    return float(x_text), float(y_text)


def test_solution_txt():
    path = '/home/user/solution.txt'
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content, f"File {path} is empty."

    parts = content.split(',')
    assert len(parts) == 2, f"Expected 2 comma-separated values in {path}, got {len(parts)}."

    try:
        x_val = float(parts[0])
        y_val = float(parts[1])
    except ValueError:
        assert False, f"Could not parse floats from {content}."

    expected_x, expected_y = reference_solution()
    tolerance = 1e-3

    assert abs(x_val - expected_x) < tolerance, f"Expected x to be near {expected_x}, got {x_val}"
    assert abs(y_val - expected_y) < tolerance, f"Expected y to be near {expected_y}, got {y_val}"
TEST_EOF

if [ "$run_ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
