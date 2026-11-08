#!/bin/bash
set -e
mkdir -p /logs/verifier

execution_ok=1
VENV_PYTHON=/home/user/env/bin/python
SCRIPT=/home/user/generate_data.py

if [ ! -f "$VENV_PYTHON" ] || [ ! -f "$SCRIPT" ]; then
    execution_ok=0
else
    rm -f /home/user/results.json /home/user/training_data.csv /home/user/attractor.png
    if ! timeout 180 "$VENV_PYTHON" "$SCRIPT"; then
        execution_ok=0
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import subprocess


def lorenz(state):
    x, y, z = state
    sigma = 10.0
    rho = 28.0
    beta = 8.0 / 3.0
    dx = sigma * (y - x)
    dy = x * (rho - z) - y
    dz = x * y - beta * z
    return [dx, dy, dz]


def euler(dt, steps):
    state = [1.0, 1.0, 1.0]
    for _ in range(steps):
        d = lorenz(state)
        state = [state[i] + dt * d[i] for i in range(3)]
    return state


def rk4(dt, steps):
    state = [1.0, 1.0, 1.0]
    for _ in range(steps):
        k1 = lorenz(state)
        s2 = [state[i] + 0.5 * dt * k1[i] for i in range(3)]
        k2 = lorenz(s2)
        s3 = [state[i] + 0.5 * dt * k2[i] for i in range(3)]
        k3 = lorenz(s3)
        s4 = [state[i] + dt * k3[i] for i in range(3)]
        k4 = lorenz(s4)
        state = [
            state[i] + (dt / 6.0) * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i])
            for i in range(3)
        ]
    return state


def rk4_trajectory(dt, steps):
    state = [1.0, 1.0, 1.0]
    trajectory = [[0.0] + state[:]]
    for step in range(1, steps + 1):
        k1 = lorenz(state)
        s2 = [state[i] + 0.5 * dt * k1[i] for i in range(3)]
        k2 = lorenz(s2)
        s3 = [state[i] + 0.5 * dt * k2[i] for i in range(3)]
        k3 = lorenz(s3)
        s4 = [state[i] + dt * k3[i] for i in range(3)]
        k4 = lorenz(s4)
        state = [
            state[i] + (dt / 6.0) * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i])
            for i in range(3)
        ]
        trajectory.append([step * dt] + state[:])
    return trajectory


def test_virtual_environment():
    """Check that the virtual environment was created and has the required packages."""
    venv_python = '/home/user/env/bin/python'
    assert os.path.isfile(venv_python), f"Virtual environment Python executable not found at {venv_python}"
    proc = subprocess.run(
        [venv_python, '-c', 'import numpy, pandas, matplotlib'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Required packages are not installed in the virtual environment: {proc.stderr}"


def test_script_exists():
    """Check that the script was created and does not use scipy.integrate."""
    script_path = '/home/user/generate_data.py'
    assert os.path.isfile(script_path), f"Script not found at {script_path}"
    with open(script_path, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=script_path)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert all(not alias.name.startswith('scipy.integrate') for alias in node.names), \
                "generate_data.py must not import scipy.integrate"
        elif isinstance(node, ast.ImportFrom):
            assert not (node.module or '').startswith('scipy.integrate'), \
                "generate_data.py must not import scipy.integrate"


def test_results_json():
    """Check the contents of results.json."""
    results_path = '/home/user/results.json'
    assert os.path.isfile(results_path), f"Results file not found at {results_path}"

    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "results.json is not a valid JSON file"

    expected = {
        'rk4_0.01': [round(x, 5) for x in rk4(0.01, 200)],
        'rk4_0.001': [round(x, 5) for x in rk4(0.001, 2000)],
        'euler_0.01': [round(x, 5) for x in euler(0.01, 200)],
    }

    for key in expected:
        assert key in data, f"Key '{key}' missing from results.json"
        assert isinstance(data[key], list) and len(data[key]) == 3, f"Value for {key} must be a three-element list"
        for i in range(3):
            assert math.isclose(data[key][i], expected[key][i], abs_tol=1e-4), \
                f"Value mismatch for {key} at index {i}. Expected approx {expected[key][i]}, got {data[key][i]}"


def test_training_data_csv():
    """Check the complete RK4 dt=0.001 trajectory in training_data.csv."""
    csv_path = '/home/user/training_data.csv'
    assert os.path.isfile(csv_path), f"CSV file not found at {csv_path}"

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 2002, f"Expected 2002 rows in CSV, found {len(rows)}"

    header = [col.strip() for col in rows[0]]
    assert header == ['t', 'x', 'y', 'z'], f"Expected header ['t', 'x', 'y', 'z'], got {header}"

    first_row = [float(val) for val in rows[1]]
    assert first_row == [0.0, 1.0, 1.0, 1.0], f"Expected first data row to be [0.0, 1.0, 1.0, 1.0], got {first_row}"

    expected = rk4_trajectory(0.001, 2000)
    for index, (row, wanted) in enumerate(zip(rows[1:], expected)):
        assert len(row) == 4, f"CSV data row {index + 1} does not have four columns"
        try:
            actual = [float(value) for value in row]
        except ValueError:
            assert False, f"CSV data row {index + 1} contains a non-numeric value"
        assert all(math.isfinite(value) for value in actual), f"CSV data row {index + 1} contains a non-finite value"
        assert math.isclose(actual[0], wanted[0], rel_tol=0.0, abs_tol=1e-9), \
            f"Incorrect time at trajectory index {index}: expected {wanted[0]}, got {actual[0]}"
        for coordinate in range(1, 4):
            assert math.isclose(actual[coordinate], wanted[coordinate], rel_tol=1e-9, abs_tol=1e-5), \
                f"Incorrect trajectory value at index {index}, column {coordinate}: expected {wanted[coordinate]}, got {actual[coordinate]}"


def test_attractor_plot():
    """Check that attractor.png is a valid, non-blank PNG image."""
    plot_path = '/home/user/attractor.png'
    assert os.path.isfile(plot_path), f"Plot file not found at {plot_path}"
    assert os.path.getsize(plot_path) > 0, f"Plot file {plot_path} is empty"
    with open(plot_path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', f"Plot file {plot_path} is not a PNG"

    checker = (
        "import json, matplotlib.image as mpimg, numpy as np; "
        "a=mpimg.imread('/home/user/attractor.png'); "
        "print(json.dumps({'shape': list(a.shape), 'finite': bool(np.isfinite(a).all()), "
        "'min': float(np.min(a)), 'max': float(np.max(a))}))"
    )
    proc = subprocess.run(
        ['/home/user/env/bin/python', '-c', checker],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"attractor.png could not be decoded: {proc.stderr}"
    info = json.loads(proc.stdout.strip())
    assert len(info['shape']) in (2, 3), f"Unexpected image shape: {info['shape']}"
    assert info['shape'][0] >= 100 and info['shape'][1] >= 100, f"Plot image is too small: {info['shape']}"
    assert info['finite'], "Plot image contains non-finite pixel values"
    assert info['max'] - info['min'] > 1e-3, "Plot image appears blank"
TEST_EOF

if [ "$execution_ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
