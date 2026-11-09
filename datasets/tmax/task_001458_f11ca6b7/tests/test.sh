#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import re
import struct
import subprocess

PYTHON = '/home/user/scipy_env/bin/python'
SCRIPT = '/home/user/run_experiment.py'
RESULT = '/home/user/quad_result.txt'
CSV_PATH = '/home/user/mc_convergence.csv'
PLOT = '/home/user/convergence.png'
EXPECTED_NS = [10000, 50000, 100000, 500000]


def analytic_integral():
    # Independent closed-form value of integral(exp(-x) * sin(100*x), x=0..5).
    return (100.0 + math.exp(-5.0) * (-math.sin(500.0) - 100.0 * math.cos(500.0))) / 10001.0


def call_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = call_name(node.value)
        return (prefix + '.' if prefix else '') + node.attr
    return ''


def test_venv_exists():
    """Verify that the virtual environment and required packages exist."""
    assert os.path.exists(PYTHON), f"Virtual environment python not found at {PYTHON}"
    assert os.access(PYTHON, os.X_OK), f"Python executable at {PYTHON} is not executable"
    proc = subprocess.run(
        [PYTHON, '-c', 'import numpy, scipy, matplotlib; print(numpy.__file__); print(scipy.__file__); print(matplotlib.__file__)'],
        text=True, capture_output=True, timeout=30
    )
    assert proc.returncode == 0, f"Required packages are unavailable in the virtual environment: {proc.stderr}"
    assert '/home/user/scipy_env/' in proc.stdout, "Required packages are not installed in the requested virtual environment"


def test_script_structure_and_execute():
    """Check required source-level settings, then execute the submitted artifact."""
    assert os.path.isfile(SCRIPT), f"Experiment script not found at {SCRIPT}"
    with open(SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    imported_roots = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported_roots.update(alias.name.split('.')[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported_roots.add(node.module.split('.')[0])
    assert {'numpy', 'scipy', 'matplotlib'} <= imported_roots, "Script must import numpy, scipy, and matplotlib"

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    quad_calls = [c for c in calls if call_name(c.func).split('.')[-1] == 'quad']
    assert quad_calls, "Script does not call scipy.integrate.quad"
    assert any(
        any(k.arg == 'limit' and isinstance(k.value, ast.Constant) and k.value.value == 1000 for k in c.keywords)
        for c in quad_calls
    ), "quad must be called with limit=1000"

    seed_calls = [c for c in calls if call_name(c.func).split('.')[-1] == 'seed']
    assert len(seed_calls) == 1, f"numpy.random.seed must be called exactly once, found {len(seed_calls)} calls"
    seed_call = seed_calls[0]
    assert (len(seed_call.args) == 1 and isinstance(seed_call.args[0], ast.Constant)
            and seed_call.args[0].value == 42), "The single random seed call must use 42"

    random_methods = {'uniform', 'random', 'random_sample', 'rand', 'randn', 'choice', 'normal', 'default_rng'}
    random_calls = [c for c in calls if call_name(c.func).split('.')[-1] in random_methods]
    if random_calls:
        assert seed_call.lineno < min(c.lineno for c in random_calls), "numpy.random.seed(42) must occur before random generation"

    for path in (RESULT, CSV_PATH, PLOT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    proc = subprocess.run([PYTHON, SCRIPT], cwd='/home/user', text=True,
                          capture_output=True, timeout=180)
    assert proc.returncode == 0, f"Experiment script failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
    for path in (RESULT, CSV_PATH, PLOT):
        assert os.path.isfile(path), f"Executing the script did not create {path}"


def test_quad_result():
    """Verify the independently computed integral and exact six-decimal formatting."""
    assert os.path.exists(RESULT), f"File not found: {RESULT}"
    with open(RESULT, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    assert re.fullmatch(r'[+-]?\d+\.\d{6}', content), \
        f"{RESULT} must contain only one float formatted to exactly 6 decimal places: {content!r}"
    try:
        val = float(content)
    except ValueError:
        assert False, f"Content of {RESULT} is not a valid float: '{content}'"
    assert 0.009 < val < 0.011, f"Computed integral {val} is far from the expected value (~0.010)"
    expected = analytic_integral()
    assert content == f'{expected:.6f}', f"Expected the integral rounded to six decimals to be {expected:.6f}, got {content}"


def expected_mc_strategies():
    """Derive seeded NumPy answers for the two standard valid convergence layouts."""
    helper = r'''
import json
import numpy as np
Ns = [10000, 50000, 100000, 500000]
def values(x):
    return [float(5.0 * np.mean(np.sin(100.0*a) * np.exp(-a))) for a in x]
np.random.seed(42)
sequential = values([np.random.uniform(0.0, 5.0, n) for n in Ns])
np.random.seed(42)
all_samples = np.random.uniform(0.0, 5.0, Ns[-1])
prefix = values([all_samples[:n] for n in Ns])
print(json.dumps([sequential, prefix]))
'''
    proc = subprocess.run([PYTHON, '-c', helper], text=True, capture_output=True, timeout=30)
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


def test_mc_convergence_csv():
    """Verify CSV structure and independently reproduce seeded Monte Carlo values."""
    assert os.path.exists(CSV_PATH), f"File not found: {CSV_PATH}"
    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, "CSV file is empty"
    assert rows[0] == ['N', 'Estimate', 'Error'], f"Incorrect CSV header: {rows[0]}"
    assert len(rows) == 5, f"CSV must contain exactly four data rows, got {len(rows)-1}"

    actual_ns = []
    estimates = []
    errors = []
    for i, row in enumerate(rows[1:], start=1):
        assert len(row) == 3, f"Row {i} does not have exactly 3 columns: {row}"
        actual_ns.append(row[0])
        try:
            estimate = float(row[1])
            error = float(row[2])
        except ValueError:
            assert False, f"Estimate or Error in row {i} is not a valid float: {row}"
        assert math.isfinite(estimate) and math.isfinite(error), f"Row {i} contains a non-finite value"
        estimates.append(estimate)
        errors.append(error)

    expected_n_strings = [str(n) for n in EXPECTED_NS]
    assert actual_ns == expected_n_strings, f"Expected N values {expected_n_strings}, but got {actual_ns}"

    strategies = expected_mc_strategies()
    matching = [candidate for candidate in strategies if all(
        math.isclose(got, want, rel_tol=0.0, abs_tol=5e-7)
        for got, want in zip(estimates, candidate)
    )]
    assert matching, f"Monte Carlo estimates do not match numpy.random.seed(42) uniform sampling: {estimates}"

    truth = analytic_integral()
    for i, (estimate, error) in enumerate(zip(estimates, errors), start=1):
        expected_error = abs(estimate - truth)
        assert math.isclose(error, expected_error, rel_tol=0.0, abs_tol=1e-6), \
            f"Incorrect Error in row {i}: expected {expected_error}, got {error}"
        assert error >= 0.0, f"Error in row {i} must be absolute/nonnegative"


def test_convergence_plot():
    """Verify that execution generated a substantive, structurally valid PNG plot."""
    assert os.path.exists(PLOT), f"Plot file not found: {PLOT}"
    assert os.path.getsize(PLOT) > 0, f"Plot file {PLOT} is empty"
    assert os.path.getsize(PLOT) > 1000, f"Plot file {PLOT} is too small to be a generated convergence plot"
    with open(PLOT, 'rb') as f:
        data = f.read()
    assert data.startswith(b'\x89PNG\r\n\x1a\n'), "convergence.png is not a PNG file"
    assert len(data) >= 33 and data[12:16] == b'IHDR', "PNG is missing its IHDR chunk"
    width, height = struct.unpack('>II', data[16:24])
    assert width >= 100 and height >= 100, f"Plot dimensions are implausibly small: {width}x{height}"
    assert b'IDAT' in data and data.endswith(b'IEND\xaeB`\x82'), "PNG data is incomplete"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
