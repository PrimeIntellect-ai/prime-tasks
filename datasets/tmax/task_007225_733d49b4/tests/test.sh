#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import numpy as np

VENV_DIR = '/home/user/etl_venv'
PYTHON_EXEC = os.path.join(VENV_DIR, 'bin', 'python')
SCRIPT_PATH = '/home/user/test_etl_bootstrap.py'
DATA_PATH = '/home/user/raw_etl_data.jsonl'
RESULTS_PATH = '/home/user/bootstrap_results.txt'


def run_submission():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    result = subprocess.run(
        [PYTHON_EXEC, SCRIPT_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'Script failed with exit code {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )
    assert os.path.isfile(RESULTS_PATH), (
        f'Script did not create {RESULTS_PATH}.'
    )

    with open(RESULTS_PATH, 'r') as f:
        return f.read().strip()


def expected_bootstrap(values):
    np.random.seed(42)
    samples = np.random.choice(
        np.asarray(values, dtype=float),
        size=(10000, len(values)),
        replace=True,
    )
    means = samples.mean(axis=1)
    lower, upper = np.percentile(means, [2.5, 97.5])
    return f'{lower:.2f},{upper:.2f}'


def write_dataset(values):
    with open(DATA_PATH, 'w') as f:
        for index, value in enumerate(values):
            f.write(json.dumps({'id': index, 'sales_amount': float(value)}) + '\n')


def test_venv_exists():
    """Verify that the virtual environment exists and has a python executable."""
    assert os.path.isdir(VENV_DIR), f"Virtual environment directory {VENV_DIR} does not exist."
    assert os.path.isfile(PYTHON_EXEC), f"Python executable not found at {PYTHON_EXEC}."
    assert os.access(PYTHON_EXEC, os.X_OK), f"Python executable at {PYTHON_EXEC} is not executable."


def test_packages_installed():
    """Verify that numpy and pandas are installed in the virtual environment."""
    result_numpy = subprocess.run([PYTHON_EXEC, '-c', 'import numpy'], capture_output=True)
    assert result_numpy.returncode == 0, "numpy is not installed in the virtual environment."

    result_pandas = subprocess.run([PYTHON_EXEC, '-c', 'import pandas'], capture_output=True)
    assert result_pandas.returncode == 0, "pandas is not installed in the virtual environment."


def test_script_exists():
    """Verify that the python script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_results_file_and_content():
    """Execute the script and verify its bootstrap results on canonical and fresh data."""
    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    canonical_result = None
    try:
        content = run_submission()
        canonical_result = content

        expected_content = "98.02,101.48"
        assert content == expected_content, f"Expected results file content '{expected_content}', but found '{content}'."

        rng = secrets.SystemRandom()
        probes = [
            [rng.uniform(-175.0, 430.0) + i * 0.137 for i in range(29)],
            [rng.uniform(800.0, 1700.0) - i * 0.219 for i in range(47)],
        ]

        for values in probes:
            expected = expected_bootstrap(values)
            write_dataset(values)
            actual = run_submission()
            assert actual == expected, (
                f'For a verifier-generated dataset, expected {expected!r} '
                f'but the script wrote {actual!r}.'
            )
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        if canonical_result is not None:
            with open(RESULTS_PATH, 'w') as f:
                f.write(canonical_result + '\n')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
