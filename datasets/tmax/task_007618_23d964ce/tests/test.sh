#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import subprocess
import sys

import numpy as np
import pytest
from scipy.special import expit

SCRIPT_PATH = '/home/user/fit_model.py'
THETA_PATH = '/home/user/theta.npy'
METRICS_PATH = '/home/user/metrics.json'


def compute_loss_stable(X, y, theta):
    z = np.dot(X, theta)
    return np.sum(np.logaddexp(0, z) - y * z)


def compute_gradient_stable(X, y, theta):
    z = np.dot(X, theta)
    return np.dot(X.T, (expit(z) - y))


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f'Missing {SCRIPT_PATH}'
    os.remove(THETA_PATH) if os.path.exists(THETA_PATH) else None
    os.remove(METRICS_PATH) if os.path.exists(METRICS_PATH) else None

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f'fit_model.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.exists(THETA_PATH), f'File {THETA_PATH} was not created by fit_model.py.'
    assert os.path.exists(METRICS_PATH), f'File {METRICS_PATH} was not created by fit_model.py.'


@pytest.fixture(scope='module')
def student_module(execute_submission):
    spec = importlib.util.spec_from_file_location('student_fit_model', SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope='module')
def expected_results():
    X_path = '/home/user/data/X.npy'
    y_path = '/home/user/data/y.npy'

    assert os.path.exists(X_path), f'Missing {X_path}'
    assert os.path.exists(y_path), f'Missing {y_path}'

    X = np.load(X_path)
    y = np.load(y_path)

    np.random.seed(42)
    theta = np.random.randn(X.shape[1])

    lr = 0.001
    max_iters = 10000
    prev_loss = float('inf')

    iters = 0
    final_loss = None
    for i in range(max_iters):
        loss = compute_loss_stable(X, y, theta)
        if abs(prev_loss - loss) < 1e-5:
            final_loss = loss
            break
        prev_loss = loss

        grad = compute_gradient_stable(X, y, theta)
        theta = theta - lr * grad
        iters += 1
        final_loss = loss

    return theta, iters, final_loss


def _is_np_call(node, parts):
    if not isinstance(node, ast.Call):
        return False
    value = node.func
    for part in reversed(parts[1:]):
        if not isinstance(value, ast.Attribute) or value.attr != part:
            return False
        value = value.value
    return isinstance(value, ast.Name) and value.id == parts[0]


def test_required_source_changes_present():
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    seed_calls = [n for n in ast.walk(tree) if _is_np_call(n, ('np', 'random', 'seed'))]
    assert len(seed_calls) == 1, 'np.random.seed must be called exactly once.'
    seed = seed_calls[0]
    assert len(seed.args) == 1 and isinstance(seed.args[0], ast.Constant) and seed.args[0].value == 42, \
        'The single np.random.seed call must use seed 42.'

    theta_randn = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        value = node.value
        if any(isinstance(t, ast.Name) and t.id == 'theta' for t in targets) and _is_np_call(value, ('np', 'random', 'randn')):
            theta_randn.append(value)
    assert theta_randn, 'theta must be initialized using np.random.randn(X.shape[1]).'
    init = theta_randn[0]
    assert len(init.args) == 1, 'np.random.randn must be called with X.shape[1].'
    arg = init.args[0]
    assert (
        isinstance(arg, ast.Subscript)
        and isinstance(arg.value, ast.Attribute)
        and isinstance(arg.value.value, ast.Name)
        and arg.value.value.id == 'X'
        and arg.value.attr == 'shape'
        and isinstance(arg.slice, ast.Constant)
        and arg.slice.value == 1
    ), 'theta must be initialized using np.random.randn(X.shape[1]).'
    assert seed.lineno < init.lineno, 'np.random.seed(42) must occur before theta initialization.'

    convergence_check = False
    for loop in (n for n in ast.walk(tree) if isinstance(n, (ast.For, ast.While))):
        for condition in (n for n in ast.walk(loop) if isinstance(n, ast.If)):
            has_break = any(isinstance(n, ast.Break) for n in ast.walk(condition))
            test = condition.test
            if not has_break or not isinstance(test, ast.Compare) or len(test.ops) != 1:
                continue
            if not isinstance(test.ops[0], ast.Lt) or len(test.comparators) != 1:
                continue
            threshold = test.comparators[0]
            left = test.left
            if (
                isinstance(threshold, ast.Constant)
                and threshold.value == 1e-5
                and isinstance(left, ast.Call)
                and isinstance(left.func, ast.Name)
                and left.func.id == 'abs'
            ):
                convergence_check = True
    assert convergence_check, 'The optimization loop must break when the absolute loss difference is strictly less than 1e-5.'


def test_loss_and_gradient_are_stable_and_correct(student_module):
    assert callable(getattr(student_module, 'compute_loss', None)), 'compute_loss is missing or not callable.'
    assert callable(getattr(student_module, 'compute_gradient', None)), 'compute_gradient is missing or not callable.'

    cases = [
        (
            np.array([[1000.0, 0.0], [-1000.0, 0.0], [750.0, -750.0], [-800.0, 900.0]]),
            np.array([1.0, 0.0, 1.0, 0.0]),
            np.array([1.0, 1.0]),
        ),
        (
            np.array([[3.2, -4.1, 0.5], [-2.0, 1.2, 7.0], [0.1, 0.2, -0.3], [8.0, -6.0, 2.0]]),
            np.array([0.0, 1.0, 1.0, 0.0]),
            np.array([-1.5, 2.25, -0.75]),
        ),
    ]

    for X, y, theta in cases:
        expected_loss = compute_loss_stable(X, y, theta)
        expected_grad = compute_gradient_stable(X, y, theta)
        with np.errstate(over='raise', invalid='raise', divide='raise'):
            actual_loss = student_module.compute_loss(X, y, theta)
            actual_grad = student_module.compute_gradient(X, y, theta)
        assert np.isfinite(actual_loss), 'compute_loss returned a non-finite value.'
        assert np.all(np.isfinite(actual_grad)), 'compute_gradient returned non-finite values.'
        assert np.allclose(actual_loss, expected_loss, rtol=1e-10, atol=1e-10), \
            'compute_loss does not implement stable binary cross-entropy.'
        assert np.asarray(actual_grad).shape == expected_grad.shape
        assert np.allclose(actual_grad, expected_grad, rtol=1e-10, atol=1e-10), \
            'compute_gradient does not implement the correct stable BCE gradient.'


def test_theta_saved_and_correct(expected_results):
    theta_path = '/home/user/theta.npy'
    assert os.path.exists(theta_path), f'File {theta_path} was not created.'

    student_theta = np.load(theta_path)
    expected_theta, _, _ = expected_results

    assert student_theta.shape == expected_theta.shape, f'theta.npy shape mismatch. Expected {expected_theta.shape}, got {student_theta.shape}'
    assert np.allclose(student_theta, expected_theta, atol=1e-3), 'The saved theta.npy does not match the expected optimized weights.'


def test_metrics_saved_and_correct(expected_results):
    metrics_path = '/home/user/metrics.json'
    assert os.path.exists(metrics_path), f'File {metrics_path} was not created.'

    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{metrics_path} does not contain valid JSON.')

    assert 'iterations' in metrics, "metrics.json is missing the 'iterations' key."
    assert 'final_loss' in metrics, "metrics.json is missing the 'final_loss' key."

    _, expected_iters, expected_loss = expected_results
    student_iters = metrics['iterations']
    student_loss = metrics['final_loss']

    assert isinstance(student_iters, int), "'iterations' in metrics.json must be an integer."
    assert isinstance(student_loss, (float, int)), "'final_loss' in metrics.json must be a float."
    assert abs(student_iters - expected_iters) <= 2, f'Expected around {expected_iters} iterations, but got {student_iters}.'
    assert abs(student_loss - expected_loss) < 1e-2, f'Expected final_loss around {expected_loss}, but got {student_loss}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
