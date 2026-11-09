#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import subprocess
import sys

import numpy as np
import pytest

SCRIPT_PATH = '/home/user/fit_model.py'
DATA_PATH = '/home/user/sensor_data.csv'
RESULT_PATH = '/home/user/model_results.json'


def run_script():
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, (
        f'fit_model.py exited with code {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert os.path.isfile(RESULT_PATH), (
        'Executing fit_model.py did not create /home/user/model_results.json.'
    )


def load_results():
    with open(RESULT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {RESULT_PATH} is not valid JSON.')


def qualified_name(node, aliases):
    if isinstance(node, ast.Name):
        return aliases.get(node.id, node.id)
    if isinstance(node, ast.Attribute):
        base = qualified_name(node.value, aliases)
        return f'{base}.{node.attr}' if base else node.attr
    return ''


def test_fit_model_script_exists_and_implements_required_operations():
    assert os.path.exists(SCRIPT_PATH), f'The script {SCRIPT_PATH} is missing.'
    assert os.path.isfile(SCRIPT_PATH), f'The path {SCRIPT_PATH} is not a file.'

    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()
    assert source.strip(), 'fit_model.py is empty.'

    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f'fit_model.py is not valid Python: {exc}')

    aliases = {}
    imported_modules = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                local = item.asname or item.name.split('.')[0]
                aliases[local] = item.name
                imported_modules.add(item.name)
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ''
            imported_modules.add(module)
            for item in node.names:
                local = item.asname or item.name
                aliases[local] = f'{module}.{item.name}' if module else item.name

    functions = {
        node.name for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    assert 'fit_chunk' in functions, 'fit_model.py must define fit_chunk.'

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    call_names = [qualified_name(node.func, aliases) for node in calls]
    terminals = [name.rsplit('.', 1)[-1] for name in call_names]

    assert any(name in ('fft', 'rfft') for name in terminals), (
        'fit_model.py must call a NumPy or SciPy FFT routine.'
    )
    assert 'svd' in terminals, 'fit_model.py must call numpy.linalg.svd.'
    assert 'lstsq' not in terminals, 'numpy.linalg.lstsq is not allowed.'
    assert 'pinv' not in terminals, 'Use the requested manual SVD pseudoinverse logic, not pinv.'
    assert not any(name == 'sklearn' or name.startswith('sklearn.') for name in imported_modules), (
        'scikit-learn is not allowed.'
    )

    assert any(name in ('ProcessPoolExecutor', 'Pool') for name in terminals), (
        'fit_model.py must construct a ProcessPoolExecutor or multiprocessing.Pool.'
    )
    parallel_calls = []
    for node, terminal in zip(calls, terminals):
        if terminal in ('submit', 'map', 'starmap', 'imap', 'imap_unordered'):
            parallel_calls.append(node)
    assert any(
        any(isinstance(child, ast.Name) and child.id == 'fit_chunk' for child in ast.walk(call))
        for call in parallel_calls
    ), 'fit_chunk must be dispatched through the process pool/executor.'


def test_model_results_json_exists_format_and_original_values_after_execution():
    run_script()
    data = load_results()

    assert 'frequencies' in data, "The key 'frequencies' is missing from the JSON output."
    assert 'weights_chunk_0' in data, "The key 'weights_chunk_0' is missing from the JSON output."
    assert isinstance(data['frequencies'], list), "'frequencies' should be a list."
    assert isinstance(data['weights_chunk_0'], list), "'weights_chunk_0' should be a list."

    freqs = data.get('frequencies', [])
    assert len(freqs) == 2, f'Expected exactly 2 dominant frequencies, got {len(freqs)}.'
    assert math.isclose(freqs[0], 5.0, abs_tol=0.05), f'Expected first frequency to be ~5.0, got {freqs[0]}.'
    assert math.isclose(freqs[1], 12.0, abs_tol=0.05), f'Expected second frequency to be ~12.0, got {freqs[1]}.'

    weights = data.get('weights_chunk_0', [])
    assert len(weights) == 5, f'Expected exactly 5 weights for the model, got {len(weights)}.'
    expected_weights = [4.981, 2.016, -1.500, -0.012, 2.992]
    for i, (act, exp) in enumerate(zip(weights, expected_weights)):
        assert math.isclose(act, exp, abs_tol=0.05), (
            f'Weight at index {i} mismatch. Expected ~{exp}, got {act}. '
            'Ensure you are using the correct chunk (rows 0-249) and SVD logic.'
        )


def test_script_on_unseen_signal_with_independently_derived_answers():
    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()
    with open(RESULT_PATH, 'rb') as f:
        original_result = f.read()

    try:
        seed = int.from_bytes(os.urandom(8), 'little')
        rng = np.random.default_rng(seed)
        fs = 80.0
        n = 800
        t = np.arange(n, dtype=float) / fs

        choices = np.array([4.0, 8.8, 14.4, 20.0, 25.6, 30.4])
        selected = rng.choice(choices, size=3, replace=False)
        true_freqs = selected[:2]
        decoy_freq = selected[2]

        phases = rng.uniform(-np.pi, np.pi, size=3)
        amplitudes = np.array([4.0, 3.0])
        scales = np.array([1.35, 0.80, 1.00, 1.10])
        bias = rng.uniform(-3.0, 3.0)
        y = np.empty(n, dtype=float)
        for chunk in range(4):
            sl = slice(chunk * 200, (chunk + 1) * 200)
            tc = t[sl]
            yc = np.full(tc.shape, bias)
            for j, freq in enumerate(true_freqs):
                yc += scales[chunk] * amplitudes[j] * np.cos(2 * np.pi * freq * tc + phases[j])
            if chunk == 0:
                yc += 8.0 * np.cos(2 * np.pi * decoy_freq * tc + phases[2])
            y[sl] = yc
        y += rng.normal(0.0, 0.005, size=n)

        np.savetxt(DATA_PATH, np.column_stack((t, y)), delimiter=',', header='t,y', comments='')

        spectrum = np.fft.fft(y)
        bins = np.fft.fftfreq(n, d=t[1] - t[0])
        positive = np.flatnonzero(bins > 0)
        dominant = positive[np.argsort(np.abs(spectrum[positive]))[-2:]]
        expected_freqs_raw = np.sort(bins[dominant])

        t0 = t[:200]
        y0 = y[:200]
        f1, f2 = expected_freqs_raw
        X = np.column_stack([
            np.ones_like(t0),
            np.cos(2 * np.pi * f1 * t0),
            np.sin(2 * np.pi * f1 * t0),
            np.cos(2 * np.pi * f2 * t0),
            np.sin(2 * np.pi * f2 * t0),
        ])
        u, singular_values, vt = np.linalg.svd(X, full_matrices=False)
        expected_beta = vt.T @ np.diag(1.0 / singular_values) @ u.T @ y0
        expected_freqs = [round(float(v), 2) for v in expected_freqs_raw]
        expected_weights = [round(float(v), 3) for v in expected_beta]

        run_script()
        data = load_results()
        assert set(data.keys()) >= {'frequencies', 'weights_chunk_0'}
        actual_freqs = data['frequencies']
        actual_weights = data['weights_chunk_0']
        assert isinstance(actual_freqs, list) and len(actual_freqs) == 2
        assert isinstance(actual_weights, list) and len(actual_weights) == 5

        for i, (actual, expected) in enumerate(zip(actual_freqs, expected_freqs)):
            assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
            assert math.isclose(actual, expected, abs_tol=0.005), (
                f'Unseen-data frequency {i} was {actual}; expected {expected}.'
            )
        for i, (actual, expected) in enumerate(zip(actual_weights, expected_weights)):
            assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
            assert math.isclose(actual, expected, abs_tol=0.0006), (
                f'Unseen-data chunk-0 weight {i} was {actual}; expected {expected}.'
            )
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        with open(RESULT_PATH, 'wb') as f:
            f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
