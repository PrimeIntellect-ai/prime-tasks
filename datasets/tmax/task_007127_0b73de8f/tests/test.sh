#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import os
import re
import subprocess
from pathlib import Path

import matplotlib.image as mpimg
import numpy as np
import pytest

HOME = Path('/home/user')
DATA = HOME / 'assay_data.npy'
MEANS = HOME / 'posterior_means.txt'
TRACE = HOME / 'mcmc_trace.png'


def parse_means(path):
    with open(path, 'r') as f:
        content = f.read().strip()
    match = re.search(r"A:\s*([0-9.]+),\s*sigma_s:\s*([0-9.]+)", content)
    assert match is not None, (
        f"Content format incorrect in {path}. Expected "
        f"'A: <value>, sigma_s: <value>', got: '{content}'"
    )
    return float(match.group(1)), float(match.group(2))


def reference_means(data):
    x = np.arange(50)
    y = np.arange(50)
    X, Y = np.meshgrid(x, y, indexing='ij')

    def log_likelihood(state):
        A, sigma_s = state
        model = A * np.exp(-((X - 25) ** 2 + (Y - 25) ** 2) /
                           (2 * sigma_s ** 2))
        return -np.sum((data - model) ** 2) / (2 * 0.5 ** 2)

    current = np.array([1.0, 1.0])
    current_ll = log_likelihood(current)
    chain = np.empty((5000, 2))
    np.random.seed(42)
    for i in range(5000):
        proposal = current + np.random.normal(0.0, 0.1, size=2)
        if 0.0 <= proposal[0] <= 10.0 and 0.1 <= proposal[1] <= 10.0:
            proposal_ll = log_likelihood(proposal)
            if np.log(np.random.random()) < proposal_ll - current_ll:
                current = proposal
                current_ll = proposal_ll
        chain[i] = current
    return chain[3000:5000].mean(axis=0)


def source_is_candidate(path):
    try:
        source = path.read_text()
        tree = ast.parse(source)
    except (OSError, UnicodeDecodeError, SyntaxError):
        return False

    required_paths = ('assay_data.npy', 'posterior_means.txt', 'mcmc_trace.png')
    if not all(name in source for name in required_paths):
        return False

    imported = set()
    has_numpy = False
    has_seed_42 = False
    has_5000 = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imported.add(alias.name.split('.')[0])
                has_numpy |= alias.name.split('.')[0] == 'numpy'
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split('.')[0])
            has_numpy |= node.module.split('.')[0] == 'numpy'
        elif isinstance(node, ast.Constant) and node.value == 5000:
            has_5000 = True
        elif isinstance(node, ast.Call):
            func = node.func
            if (isinstance(func, ast.Attribute) and func.attr == 'seed' and
                    len(node.args) >= 1 and isinstance(node.args[0], ast.Constant) and
                    node.args[0].value == 42):
                has_seed_42 = True

    assert not ({'emcee', 'pymc', 'pymc3', 'scipy'} & imported), (
        f'{path} uses a prohibited external sampling/optimization library'
    )
    assert has_numpy, f'{path} does not use numpy'
    assert has_seed_42, f'{path} does not set the required random seed 42'
    assert has_5000, f'{path} does not contain the required 5000-iteration count'
    return True


def clear_outputs():
    for path in (MEANS, TRACE):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def execute_script(script, data_bytes):
    DATA.write_bytes(data_bytes)
    before_hash = hashlib.sha256(data_bytes).hexdigest()
    clear_outputs()
    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    result = subprocess.run(
        ['python3', str(script)], cwd=str(script.parent), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
    )
    assert result.returncode == 0, (
        f'Script {script} failed when executed.\nstdout:\n{result.stdout}\n'
        f'stderr:\n{result.stderr}'
    )
    assert MEANS.is_file(), f'{script} did not create {MEANS}'
    assert TRACE.is_file(), f'{script} did not create {TRACE}'
    assert hashlib.sha256(DATA.read_bytes()).hexdigest() == before_hash, (
        f'{script} modified the input dataset'
    )
    return parse_means(MEANS)


@pytest.fixture(scope='session', autouse=True)
def execute_and_exercise_submission():
    original_bytes = DATA.read_bytes()
    original_data = np.load(DATA)
    selected = None
    try:
        candidates = sorted(
            p for p in HOME.rglob('*.py')
            if p.is_file() and source_is_candidate(p)
        )
        assert candidates, 'No MCMC Python script was found under /home/user'

        failures = []
        for candidate in candidates:
            try:
                execute_script(candidate, original_bytes)
                selected = candidate
                break
            except Exception as exc:
                failures.append(f'{candidate}: {exc}')
        assert selected is not None, 'No submitted script executed successfully: ' + '; '.join(failures)

        expected_original = reference_means(original_data)
        actual_original = np.array(parse_means(MEANS))
        assert np.all(np.abs(actual_original - expected_original) <= 0.005), (
            f'Script output {actual_original} does not match an independently '
            f'executed 5000-step chain {expected_original}'
        )

        rng = np.random.RandomState(777)
        x = np.arange(50)
        X, Y = np.meshgrid(x, x, indexing='ij')
        custom_data = 3.7 * np.exp(-((X - 25) ** 2 + (Y - 25) ** 2) /
                                   (2 * 5.1 ** 2))
        custom_data += rng.normal(0, 0.5, size=(50, 50))
        custom_path = '/tmp/verifier_assay_data.npy'
        np.save(custom_path, custom_data)
        custom_bytes = Path(custom_path).read_bytes()

        actual_custom = np.array(execute_script(selected, custom_bytes))
        expected_custom = reference_means(custom_data)
        assert np.all(np.abs(actual_custom - expected_custom) <= 0.005), (
            f'Script failed on independently generated assay data: got '
            f'{actual_custom}, expected {expected_custom}'
        )

        # Recreate the requested final artifacts for the original assay.
        execute_script(selected, original_bytes)
    finally:
        DATA.write_bytes(original_bytes)


def test_posterior_means_file():
    txt_path = "/home/user/posterior_means.txt"
    assert os.path.isfile(txt_path), f"File not found: {txt_path}"

    with open(txt_path, "r") as f:
        content = f.read().strip()

    # Match the expected format: A: <value>, sigma_s: <value>
    match = re.search(r"A:\s*([0-9.]+),\s*sigma_s:\s*([0-9.]+)", content)
    assert match is not None, f"Content format incorrect in {txt_path}. Expected 'A: <value>, sigma_s: <value>', got: '{content}'"

    A_val = float(match.group(1))
    sigma_s_val = float(match.group(2))

    # The exact expected values with seed 42 are 5.518 and 3.205.
    # We allow a very small tolerance to account for floating point differences.
    assert abs(A_val - 5.518) <= 0.005, f"Expected A to be approximately 5.518, got {A_val}"
    assert abs(sigma_s_val - 3.205) <= 0.005, f"Expected sigma_s to be approximately 3.205, got {sigma_s_val}"


def test_mcmc_trace_png():
    png_path = "/home/user/mcmc_trace.png"
    assert os.path.isfile(png_path), f"Image file not found: {png_path}"
    assert os.path.getsize(png_path) > 0, f"Image file {png_path} is empty"
    with open(png_path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', f'{png_path} is not a PNG file'
    image = mpimg.imread(png_path)
    assert image.ndim in (2, 3), f'{png_path} is not a readable image'
    assert image.shape[0] >= 100 and image.shape[1] >= 100, f'{png_path} is too small'
    assert float(np.std(image)) > 0.01, f'{png_path} appears blank'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
