#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
import uuid

import numpy as np
import pytest

HOME = '/home/user'
PRED_PATH = '/home/user/predictions.txt'
CPP_PATH = '/home/user/surrogate.cpp'
SIM_PATH = '/app/simulator'


def f(x):
    return np.exp(-100 * (x - 0.3)**2) + 0.5 * np.sin(20 * x) + 1.0 / (1.0 + 1000 * (x - 0.8)**2)


def load_numeric(path):
    if not os.path.isfile(path) or os.path.getsize(path) > 5_000_000:
        return None
    for delimiter in (None, ','):
        try:
            a = np.loadtxt(path, delimiter=delimiter)
            if np.size(a) and np.all(np.isfinite(a)):
                return np.asarray(a, dtype=float)
        except Exception:
            pass
    return None


def simulator_values(x):
    with tempfile.NamedTemporaryFile(mode='w', delete=False) as inp:
        for value in x:
            inp.write(f'{value:.17g}\n')
        input_path = inp.name
    try:
        result = subprocess.run(
            [SIM_PATH, input_path], text=True, capture_output=True, timeout=15
        )
        assert result.returncode == 0, 'The simulator failed while validating the submitted mesh'
        values = np.fromstring(result.stdout, sep=' ')
        assert values.size == 150, 'Simulator did not return 150 values for the submitted mesh'
        return values
    finally:
        os.unlink(input_path)


def valid_mesh(x):
    x = np.asarray(x, dtype=float).reshape(-1)
    if x.size != 150 or not np.all(np.isfinite(x)):
        return False
    if np.any(x < 0) or np.any(x > 1) or np.any(np.diff(x) <= 0):
        return False
    if not np.isclose(x[0], 0.0, atol=1e-10) or not np.isclose(x[-1], 1.0, atol=1e-10):
        return False
    spacing = np.diff(x)
    return np.ptp(spacing) > 1e-6


def find_exact_point_sets():
    files = []
    for root, dirs, names in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith('.verifier')]
        for name in names:
            path = os.path.join(root, name)
            if path in (PRED_PATH, CPP_PATH, '/home/user/bootstrap_ci.txt'):
                continue
            data = load_numeric(path)
            if data is not None:
                files.append((path, data))

    candidates = []

    # A conventional two-column x,y file.
    for path, data in files:
        if data.ndim == 2 and data.shape == (150, 2):
            order = np.argsort(data[:, 0])
            x = data[order, 0]
            y = data[order, 1]
            if valid_mesh(x):
                truth = simulator_values(x)
                if np.allclose(y, truth, rtol=3e-5, atol=3e-5):
                    candidates.append({
                        'x': x, 'y': y, 'point_path': path,
                        'x_path': None, 'y_path': None
                    })

    # Also accept separate 150-value mesh and simulator-output files.
    vectors = []
    for path, data in files:
        if data.ndim == 1 and data.size == 150:
            vectors.append((path, data.reshape(-1)))
        elif data.ndim == 2 and data.shape in ((150, 1), (1, 150)):
            vectors.append((path, data.reshape(-1)))

    for x_path, x_raw in vectors:
        order = np.argsort(x_raw)
        x = x_raw[order]
        if not valid_mesh(x):
            continue
        truth = simulator_values(x)
        for y_path, y_raw in vectors:
            if y_path == x_path:
                continue
            y = y_raw[order]
            if np.allclose(y, truth, rtol=3e-5, atol=3e-5):
                candidates.append({
                    'x': x, 'y': y, 'point_path': None,
                    'x_path': x_path, 'y_path': y_path
                })

    return candidates


def output_matches_candidate(candidate):
    try:
        generated = np.loadtxt(PRED_PATH)
    except Exception:
        return False
    if generated.ndim != 1 or generated.size != 10000 or not np.all(np.isfinite(generated)):
        return False
    dense_x = np.arange(10000, dtype=float) / 9999.0
    expected = np.interp(dense_x, candidate['x'], candidate['y'])
    return np.allclose(generated, expected, rtol=3e-5, atol=3e-5)


def test_00_cpp_program_generates_linear_interpolation_from_exact_150_point_mesh():
    assert os.path.exists(CPP_PATH), f'{CPP_PATH} does not exist. A C++ implementation is required.'

    candidates = find_exact_point_sets()
    assert candidates, (
        'Could not find an exact 150-point non-uniform mesh and corresponding simulator values '
        'under /home/user'
    )

    executable = '/home/user/.verifier_surrogate'
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', CPP_PATH, '-o', executable],
        text=True, capture_output=True, timeout=30
    )
    assert compile_result.returncode == 0, f'Failed to compile surrogate.cpp:\n{compile_result.stderr}'
    os.chmod(executable, 0o755)

    backup_dir = tempfile.mkdtemp(prefix='surrogate-backup-')
    os.chmod(backup_dir, 0o700)
    backup_pred = os.path.join(backup_dir, 'predictions.txt')
    if os.path.exists(PRED_PATH):
        os.replace(PRED_PATH, backup_pred)

    hidden_sim = f'/app/.simulator-verifier-{uuid.uuid4().hex}'
    os.replace(SIM_PATH, hidden_sim)
    old_mode = stat.S_IMODE(os.stat(hidden_sim).st_mode)
    os.chmod(hidden_sim, 0)

    success = False
    try:
        invocations = [[executable]]
        for candidate in candidates:
            if candidate['point_path']:
                invocations.extend([
                    [executable, candidate['point_path']],
                    [executable, candidate['point_path'], PRED_PATH],
                ])
            else:
                invocations.extend([
                    [executable, candidate['x_path'], candidate['y_path']],
                    [executable, candidate['x_path'], candidate['y_path'], PRED_PATH],
                ])

        for command in invocations:
            if os.path.exists(PRED_PATH):
                os.unlink(PRED_PATH)
            result = subprocess.run(
                ['runuser', '-u', 'user', '--', 'timeout', '20'] + command,
                cwd=HOME, text=True, capture_output=True, timeout=25
            )
            if result.returncode != 0 or not os.path.exists(PRED_PATH):
                continue
            if any(output_matches_candidate(candidate) for candidate in candidates):
                success = True
                break
    finally:
        os.chmod(hidden_sim, old_mode)
        os.replace(hidden_sim, SIM_PATH)
        if not success and os.path.exists(backup_pred):
            if os.path.exists(PRED_PATH):
                os.unlink(PRED_PATH)
            os.replace(backup_pred, PRED_PATH)
        shutil.rmtree(backup_dir, ignore_errors=True)
        try:
            os.unlink(executable)
        except FileNotFoundError:
            pass

    assert success, (
        'The compiled C++ program did not generate predictions.txt as linear interpolation '
        'of the submitted exact 150-point mesh while the simulator was unavailable'
    )


def test_predictions_mse():
    """Check that predictions.txt exists, has 10000 lines, and MSE < 0.001."""
    pred_path = '/home/user/predictions.txt'
    assert os.path.exists(pred_path), f"{pred_path} does not exist"

    try:
        y_pred = np.loadtxt(pred_path)
    except Exception as e:
        pytest.fail(f"Failed to load {pred_path}: {e}")

    assert len(y_pred) == 10000, f"Expected exactly 10000 predictions, got {len(y_pred)}"

    x_dense = np.linspace(0, 1, 10000)
    y_true = f(x_dense)

    mse = np.mean((y_true - y_pred)**2)
    assert mse < 0.001, f"MSE {mse:.6f} is not < 0.001. The mesh refinement may not be optimal."


def test_bootstrap_ci_format():
    """Check that bootstrap_ci.txt exists, is formatted correctly, and is a valid bootstrap CI."""
    ci_path = '/home/user/bootstrap_ci.txt'
    assert os.path.exists(ci_path), f"{ci_path} does not exist"

    with open(ci_path, 'r') as f_ci:
        content = f_ci.read().strip()

    parts = content.split(',')
    assert len(parts) == 2, f"Expected format 'lower,upper', got '{content}'"

    try:
        lower = float(parts[0])
        upper = float(parts[1])
    except ValueError:
        pytest.fail(f"Could not parse '{content}' as comma-separated floats")

    assert lower <= upper, f"Lower bound {lower} is greater than upper bound {upper}"
    assert np.isfinite(lower) and np.isfinite(upper), 'Bootstrap bounds must be finite'

    predictions = np.loadtxt(PRED_PATH)
    mean = float(np.mean(predictions))
    assert lower < mean < upper, 'The bootstrap confidence interval must contain the predicted mean'

    # Independently perform the required 1,000-iteration percentile bootstrap. Different valid
    # random seeds have small variation, so use a tolerance while rejecting fabricated bounds.
    rng = np.random.default_rng(8675309)
    boot_means = np.empty(1000)
    for start in range(0, 1000, 25):
        indices = rng.integers(0, predictions.size, size=(25, predictions.size))
        boot_means[start:start + 25] = predictions[indices].mean(axis=1)
    ref_lower, ref_upper = np.percentile(boot_means, [2.5, 97.5])
    tolerance = max(0.006, 0.35 * (ref_upper - ref_lower))
    assert abs(lower - ref_lower) <= tolerance, (
        f'Lower bound {lower} is inconsistent with a 1,000-iteration 95% bootstrap CI'
    )
    assert abs(upper - ref_upper) <= tolerance, (
        f'Upper bound {upper} is inconsistent with a 1,000-iteration 95% bootstrap CI'
    )


def test_cpp_source_exists():
    """Check that the C++ source file exists."""
    cpp_path = '/home/user/surrogate.cpp'
    assert os.path.exists(cpp_path), f"{cpp_path} does not exist. A C++ implementation is required."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
