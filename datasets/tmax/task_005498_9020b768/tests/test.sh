#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import inspect
import os
import re
import subprocess
import sys

import numpy as np
import pytest

SCRIPT = "/home/user/model_fit.py"
RESULT = "/home/user/fit_result.txt"


def load_submission():
    assert os.path.exists(SCRIPT), f"Fail: {SCRIPT} not found."
    assert os.path.isfile(SCRIPT), f"Fail: {SCRIPT} is not a regular file."
    spec = importlib.util.spec_from_file_location("submitted_model_fit", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expected_mc(a, n_samples, seed):
    rng = np.random.RandomState(seed)
    samples = rng.uniform(0, 2, n_samples)
    return 2.0 * np.mean(a * np.sin(samples) * np.exp(-(samples ** 2)))


def test_integrate_mc_implementation():
    module = load_submission()
    assert callable(getattr(module, "integrate_mc", None)), "Fail: integrate_mc is missing or not callable."

    signature = inspect.signature(module.integrate_mc)
    assert signature.parameters["n_samples"].default == 1000000, "Fail: do not change the number of samples."
    assert signature.parameters["seed"].default == 42, "Fail: do not change the random seed."

    for a, n_samples, seed in [(1.25, 12031, 17), (-0.8, 9733, 91), (2.4, 15007, 123)]:
        actual = module.integrate_mc(a, n_samples=n_samples, seed=seed)
        expected = expected_mc(a, n_samples, seed)
        assert np.isfinite(actual), "Fail: integrate_mc returned a non-finite value."
        assert np.isclose(actual, expected, rtol=1e-12, atol=1e-12), (
            f"Fail: integrate_mc({a}, n_samples={n_samples}, seed={seed}) "
            f"returned {actual}, expected {expected}."
        )


def test_script_runs_and_fit_result_exists_and_correct():
    if os.path.lexists(RESULT):
        os.remove(RESULT)

    completed = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert completed.returncode == 0, f"Fail: model_fit.py did not run successfully:\n{completed.stdout}"
    assert os.path.exists(RESULT), f"Fail: {RESULT} not found after running model_fit.py."
    assert os.path.isfile(RESULT), f"Fail: {RESULT} is not a regular file."

    with open(RESULT, "r") as f:
        content = f.read().strip()

    assert re.fullmatch(r"[+-]?\d+\.\d{4}", content), (
        f"Fail: The content of {RESULT} ('{content}') is not formatted to 4 decimal places."
    )
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Fail: The content of {RESULT} ('{content}') is not a valid float.")

    assert 3.5300 <= val <= 3.5450, (
        f"Fail: Value {val} is out of the expected bounds [3.5300, 3.5450]. "
        "The Monte Carlo integration might still be incorrect."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
