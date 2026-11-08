#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import subprocess
import sys

SCRIPT_PATH = '/home/user/stable_fit.py'
COEFFS_PATH = '/home/user/coeffs.txt'
MSE_PATH = '/home/user/mse.txt'
DATA_PATH = '/home/user/signal.h5'


def run_script():
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'stable_fit.py failed with exit code {result.returncode}. '
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )


def get_expected_values():
    """Dynamically compute the expected coefficients and MSE."""
    code = """
import h5py
import numpy as np
with h5py.File('/home/user/signal.h5', 'r') as f:
    t = f['t'][:]
    signal = f['signal'][:]
coeffs_fit = np.polyfit(t, signal, 12)
mse = np.mean((np.polyval(coeffs_fit, t) - signal)**2)
for c in coeffs_fit:
    print(f"{c:.8f}")
print(f"{mse:.8f}")
"""
    result = subprocess.run([sys.executable, '-c', code], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f'Failed to compute expected values: {result.stderr}')

    lines = result.stdout.strip().split('\n')
    return lines[:13], lines[13]


def assert_outputs_match_expected():
    expected_coeffs, expected_mse = get_expected_values()

    assert os.path.isfile(COEFFS_PATH), f'The file {COEFFS_PATH} is missing.'
    with open(COEFFS_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert len(actual_lines) == 13, f'Expected 13 coefficients, found {len(actual_lines)}.'
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_coeffs)):
        assert abs(float(actual) - float(expected)) < 1e-6, (
            f'Coefficient at index {i} (degree {12-i}) does not match. '
            f'Expected {expected}, got {actual}.'
        )

    assert os.path.isfile(MSE_PATH), f'The file {MSE_PATH} is missing.'
    with open(MSE_PATH, 'r') as f:
        actual_mse_str = f.read().strip()
    assert actual_mse_str, 'The mse.txt file is empty.'
    assert abs(float(actual_mse_str) - float(expected_mse)) < 1e-6, (
        f'MSE does not match. Expected {expected_mse}, got {actual_mse_str}.'
    )


def is_transpose_expression(node):
    if isinstance(node, ast.Attribute) and node.attr == 'T':
        return True
    if isinstance(node, ast.Call):
        func = node.func
        if isinstance(func, ast.Attribute) and func.attr in {'transpose', 'swapaxes'}:
            return True
        if isinstance(func, ast.Name) and func.id in {'transpose', 'swapaxes'}:
            return True
    return False


def test_stable_fit_script_exists():
    """Check that the stable_fit.py script exists and is valid Python."""
    assert os.path.isfile(SCRIPT_PATH), f'The script {SCRIPT_PATH} is missing.'
    assert os.path.getsize(SCRIPT_PATH) > 0, f'The script {SCRIPT_PATH} is empty.'

    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    # Reject direct matrix inversion and explicit transpose-products used to
    # construct normal equations, while allowing stable lstsq/SVD/QR/polyfit.
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func = node.func
            name = func.attr if isinstance(func, ast.Attribute) else (func.id if isinstance(func, ast.Name) else '')
            assert name not in {'inv', 'inverse'}, (
                'stable_fit.py must not explicitly invert a matrix; use a stable least-squares method.'
            )
            if name in {'dot', 'matmul'}:
                receiver = func.value if isinstance(func, ast.Attribute) else None
                operands = ([receiver] if receiver is not None else []) + list(node.args)
                assert not any(is_transpose_expression(op) for op in operands), (
                    'stable_fit.py explicitly forms a transpose-product; do not form the normal equations.'
                )
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.MatMult):
            assert not (is_transpose_expression(node.left) or is_transpose_expression(node.right)), (
                'stable_fit.py explicitly forms a transpose-product; do not form the normal equations.'
            )


def test_script_executes_on_original_input():
    """Execute the submitted artifact rather than trusting pre-created outputs."""
    for path in (COEFFS_PATH, MSE_PATH):
        if os.path.exists(path):
            os.remove(path)
    run_script()


def test_coefficients_file():
    """Check that coeffs.txt contains the correct polynomial coefficients."""
    expected_coeffs, _ = get_expected_values()
    assert os.path.isfile(COEFFS_PATH), f'The file {COEFFS_PATH} is missing.'

    with open(COEFFS_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == 13, f'Expected 13 coefficients, found {len(actual_lines)}.'
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_coeffs)):
        assert abs(float(actual) - float(expected)) < 1e-6, \
            f'Coefficient at index {i} (degree {12-i}) does not match. Expected {expected}, got {actual}.'


def test_mse_file():
    """Check that mse.txt contains the correct Mean Squared Error."""
    _, expected_mse = get_expected_values()
    assert os.path.isfile(MSE_PATH), f'The file {MSE_PATH} is missing.'

    with open(MSE_PATH, 'r') as f:
        actual_mse_str = f.read().strip()

    assert actual_mse_str, 'The mse.txt file is empty.'
    assert abs(float(actual_mse_str) - float(expected_mse)) < 1e-6, \
        f'MSE does not match. Expected {expected_mse}, got {actual_mse_str}.'


def test_script_reads_and_fits_changed_hdf5_input():
    """Exercise the script on verifier-generated data whose answers are derived at test time."""
    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    generation_code = """
import h5py
import numpy as np
rng = np.random.default_rng(8675309)
t = np.linspace(0.0, 5.0, 237)
coeffs = rng.uniform(-0.75, 0.75, 13)
signal = np.polyval(coeffs, t) + rng.normal(0.0, 0.05, t.shape)
with h5py.File('/home/user/signal.h5', 'w') as f:
    f.create_dataset('t', data=t)
    f.create_dataset('signal', data=signal)
"""
    restore_result = None
    try:
        generated = subprocess.run([sys.executable, '-c', generation_code], capture_output=True, text=True)
        assert generated.returncode == 0, generated.stderr
        for path in (COEFFS_PATH, MSE_PATH):
            if os.path.exists(path):
                os.remove(path)
        run_script()
        assert_outputs_match_expected()
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        for path in (COEFFS_PATH, MSE_PATH):
            if os.path.exists(path):
                os.remove(path)
        restore_result = subprocess.run(
            [sys.executable, SCRIPT_PATH], cwd='/home/user', capture_output=True, text=True, timeout=60
        )

    assert restore_result.returncode == 0, (
        f'stable_fit.py failed after restoring the original input: {restore_result.stderr}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
