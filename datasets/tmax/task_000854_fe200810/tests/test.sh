#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import importlib.util
import io
import os
import subprocess

import numpy as np
import pytest

BUILD_SYSTEM_DIR = "/home/user/build_system"
TRAIN_PY = os.path.join(BUILD_SYSTEM_DIR, "train.py")
WEIGHTS_NPY = os.path.join(BUILD_SYSTEM_DIR, "weights.npy")

CANONICAL_X = np.array([
    [0.5, 1.2, -0.5, 1000.0],
    [-1.0, 0.0, 2.0, -2000.0],
    [1.5, -1.5, 0.0, 1500.0],
    [0.0, 0.5, -1.0, 500.0],
    [-0.5, -0.5, 1.5, -500.0],
    [2.0, 1.0, 1.0, 2000.0],
    [-2.0, -1.0, -1.0, -2500.0],
    [1.0, 2.0, -2.0, 1200.0],
    [-1.5, -2.0, 2.5, -1800.0],
    [0.2, 0.8, -0.2, 800.0],
], dtype=float)
CANONICAL_Y = np.array([5.0, -10.0, 7.5, 2.5, -2.5, 10.0, -12.5, 6.0, -9.0, 4.0])


def import_submission():
    spec = importlib.util.spec_from_file_location("submitted_train", TRAIN_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def required_preprocess(X):
    return (X - np.mean(X, axis=0)) / np.std(X, axis=0)


def required_training(X, y):
    np.random.seed(42)
    weights = np.random.randn(X.shape[1])
    for _ in range(100):
        predictions = X.dot(weights)
        errors = predictions - y
        gradient = X.T.dot(errors) / len(y)
        weights -= 0.01 * gradient
        loss = np.mean(errors ** 2)
    return weights, loss


def test_train_py_exists():
    assert os.path.exists(TRAIN_PY), f"File {TRAIN_PY} does not exist. It should not have been deleted."
    assert os.path.isfile(TRAIN_PY), f"Path {TRAIN_PY} is not a file."


def test_train_script_execution():
    if os.path.exists(WEIGHTS_NPY):
        os.remove(WEIGHTS_NPY)

    try:
        result = subprocess.run(
            ["python3", TRAIN_PY],
            cwd=BUILD_SYSTEM_DIR,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Execution of train.py timed out. It should complete quickly.")

    assert result.returncode == 0, (
        f"train.py failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert "Build passed!" in result.stdout, "The script did not print 'Build passed!' as expected."


def test_weights_npy_exists():
    assert os.path.exists(WEIGHTS_NPY), f"File {WEIGHTS_NPY} was not created. Training might have failed."
    assert os.path.isfile(WEIGHTS_NPY), f"Path {WEIGHTS_NPY} is not a file."


def test_preprocess_scales_every_feature_on_derived_input():
    module = import_submission()
    assert callable(getattr(module, "preprocess", None)), "train.py must define preprocess(X)."

    seed = int.from_bytes(os.urandom(8), "little")
    rng = np.random.default_rng(seed)
    X = rng.normal(size=(31, 4))
    X = X * np.array([0.7, 3.0, 11.0, 1700.0]) + np.array([2.0, -5.0, 20.0, 8000.0])
    expected = required_preprocess(X.copy())
    actual = np.asarray(module.preprocess(X.copy()))

    assert actual.shape == expected.shape
    assert np.all(np.isfinite(actual)), "Preprocessing produced non-finite values."
    assert np.allclose(actual, expected, rtol=1e-10, atol=1e-10), (
        "preprocess must standardize all four feature columns, including column D."
    )


def test_training_loop_produces_derived_expected_weights(tmp_path, monkeypatch):
    module = import_submission()
    assert callable(getattr(module, "train", None)), "train.py must define train(X, y)."

    seed = int.from_bytes(os.urandom(8), "little")
    rng = np.random.default_rng(seed)
    raw_X = rng.normal(size=(43, 4)) * np.array([1.0, 2.0, 5.0, 900.0])
    X = required_preprocess(raw_X)
    target_weights = rng.normal(size=4)
    y = X.dot(target_weights) + rng.normal(scale=0.05, size=len(X))
    expected_weights, expected_loss = required_training(X.copy(), y.copy())
    assert expected_loss < 15.0

    monkeypatch.chdir(tmp_path)
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        module.train(X.copy(), y.copy())

    generated = tmp_path / "weights.npy"
    assert generated.is_file(), "train() did not generate weights.npy."
    actual_weights = np.load(generated, allow_pickle=False)
    assert actual_weights.shape == (4,)
    assert np.all(np.isfinite(actual_weights))
    assert np.allclose(actual_weights, expected_weights, rtol=1e-10, atol=1e-10), (
        "Training does not use the required seed, learning rate, epoch count, and gradient-descent model."
    )
    assert "Build passed!" in output.getvalue()


def test_end_to_end_weights_match_required_pipeline():
    expected_X = required_preprocess(CANONICAL_X.copy())
    expected_weights, expected_loss = required_training(expected_X, CANONICAL_Y.copy())
    assert expected_loss < 15.0

    actual_weights = np.load(WEIGHTS_NPY, allow_pickle=False)
    assert actual_weights.shape == (4,), "weights.npy has the wrong shape."
    assert np.all(np.isfinite(actual_weights)), "weights.npy contains NaN or Inf."
    assert np.allclose(actual_weights, expected_weights, rtol=1e-10, atol=1e-10), (
        "The generated weights do not match the required preprocessing and training pipeline."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
