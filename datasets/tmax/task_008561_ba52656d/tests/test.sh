#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from scipy.integrate import odeint

CSV_PATH = Path('/home/user/protein_kinetics.csv')
RESULT_PATH = Path('/home/user/analysis_result.json')


def model(y, t, k_UI, k_IU, k_IB, k_BI):
    U, I, B = y
    return [
        -k_UI * U + k_IU * I,
        k_UI * U - (k_IU + k_IB) * I + k_BI * B,
        k_IB * I - k_BI * B,
    ]


def reference_analysis(csv_path):
    table = np.genfromtxt(csv_path, delimiter=',', names=True)
    times = np.asarray(table['time'], dtype=float)
    observed = np.column_stack((table['U'], table['I'], table['B']))

    def log_likelihood(params):
        predicted = odeint(model, [1.0, 0.0, 0.0], times, args=tuple(params))
        return -np.sum((observed - predicted) ** 2) / (2.0 * 0.05 ** 2)

    np.random.seed(42)
    current = np.full(4, 0.5, dtype=float)
    current_ll = log_likelihood(current)
    samples = []

    for step in range(6000):
        proposal = np.random.normal(current, 0.05, size=4)
        if np.all((proposal >= 0.01) & (proposal <= 2.0)):
            proposal_ll = log_likelihood(proposal)
            log_alpha = proposal_ll - current_ll
        else:
            proposal_ll = -np.inf
            log_alpha = -np.inf

        if np.log(np.random.random()) < log_alpha:
            current = proposal
            current_ll = proposal_ll

        if step >= 1000:
            samples.append(current.copy())

    samples = np.asarray(samples)
    probability = float(np.mean(samples[:, 0] > samples[:, 2]))
    return {
        'mean_k_UI': float(np.mean(samples[:, 0])),
        'mean_k_IB': float(np.mean(samples[:, 2])),
        'p_k_UI_greater_k_IB': probability,
        'reject_null': probability > 0.95,
    }


def load_result():
    assert RESULT_PATH.is_file(), f'Expected output file {RESULT_PATH} is missing.'
    try:
        with RESULT_PATH.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {RESULT_PATH} is not valid JSON.') from exc


def validate_original_assertions(data):
    expected_keys = {'mean_k_UI', 'mean_k_IB', 'p_k_UI_greater_k_IB', 'reject_null'}
    actual_keys = set(data.keys())
    assert expected_keys.issubset(actual_keys), (
        f'Missing keys in JSON. Expected {expected_keys}, found {actual_keys}.'
    )

    mean_k_UI = data['mean_k_UI']
    mean_k_IB = data['mean_k_IB']
    probability = data['p_k_UI_greater_k_IB']
    reject_null = data['reject_null']

    assert isinstance(mean_k_UI, (int, float)), f'mean_k_UI must be a float, got {type(mean_k_UI)}'
    assert isinstance(mean_k_IB, (int, float)), f'mean_k_IB must be a float, got {type(mean_k_IB)}'
    assert isinstance(probability, (int, float)), f'p_k_UI_greater_k_IB must be a float, got {type(probability)}'
    assert isinstance(reject_null, bool), f'reject_null must be a boolean, got {type(reject_null)}'

    assert 1.0 < mean_k_UI < 1.4, f'mean_k_UI out of expected bounds (1.0, 1.4): {mean_k_UI}'
    assert 0.2 < mean_k_IB < 0.6, f'mean_k_IB out of expected bounds (0.2, 0.6): {mean_k_IB}'
    assert probability > 0.95, f'p_k_UI_greater_k_IB should be > 0.95, got {probability}'
    assert reject_null is True, f'reject_null should be True, got {reject_null}'

    for key in ('mean_k_UI', 'mean_k_IB', 'p_k_UI_greater_k_IB'):
        assert math.isfinite(float(data[key])), f'{key} must be finite'
    assert 0.0 <= probability <= 1.0
    assert abs(probability * 5000 - round(probability * 5000)) < 1e-7, (
        'Posterior probability must be a fraction of the 5,000 kept samples.'
    )


def find_and_run_script():
    candidates = []
    source_corpus = []
    for path in Path('/home/user').rglob('*.py'):
        if not path.is_file():
            continue
        try:
            text = path.read_text(errors='ignore')
        except OSError:
            continue
        source_corpus.append(text.lower())
        if 'analysis_result.json' in text and 'protein_kinetics.csv' in text:
            score = sum(token in text.lower() for token in (
                'mcmc', 'metropolis', 'odeint', 'solve_ivp', 'random.normal',
                '5000', '1000', '0.05', 'k_ui', 'k_ib'
            ))
            candidates.append((score, path))

    assert candidates, 'No Python analysis script reading the CSV and writing analysis_result.json was found.'

    corpus = '\n'.join(source_corpus)
    for token in ('k_ui', 'k_iu', 'k_ib', 'k_bi', '1000', '5000'):
        assert token in corpus, f'The submitted Python code does not contain required MCMC element: {token}'
    assert ('odeint' in corpus or 'solve_ivp' in corpus), 'The submitted code does not use an allowed ODE solver.'
    assert ('random.normal' in corpus or '.normal(' in corpus), 'The submitted code lacks the normal MCMC proposal.'
    assert '42' in corpus and 'seed' in corpus, 'The submitted code does not set the required random seed 42.'

    errors = []
    for _, path in sorted(candidates, key=lambda item: (-item[0], str(item[1]))):
        RESULT_PATH.unlink(missing_ok=True)
        try:
            completed = subprocess.run(
                ['python3', str(path)],
                cwd=str(path.parent),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=240,
            )
        except subprocess.TimeoutExpired:
            errors.append(f'{path}: timed out')
            continue
        if completed.returncode == 0 and RESULT_PATH.is_file():
            try:
                load_result()
                return path
            except AssertionError as exc:
                errors.append(f'{path}: {exc}')
        else:
            errors.append(f'{path}: exit {completed.returncode}: {completed.stderr[-500:]}')

    raise AssertionError('No submitted analysis script successfully produced the result. ' + ' | '.join(errors))


def run_selected_script(path):
    RESULT_PATH.unlink(missing_ok=True)
    completed = subprocess.run(
        ['python3', str(path)],
        cwd=str(path.parent),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
    )
    assert completed.returncode == 0, f'Analysis script failed: {completed.stderr[-1000:]}'
    return load_result()


def write_alternate_dataset(path):
    times = np.linspace(0.0, 10.0, 50)
    values = odeint(model, [1.0, 0.0, 0.0], times, args=(0.30, 0.18, 1.25, 0.12))
    with open(path, 'w') as f:
        f.write('time,U,I,B\n')
        for t, row in zip(times, values):
            f.write(f'{t:.17g},{row[0]:.17g},{row[1]:.17g},{row[2]:.17g}\n')


def test_analysis_script_and_result():
    assert CSV_PATH.is_file(), f'Input dataset {CSV_PATH} is missing.'

    with tempfile.TemporaryDirectory() as tmpdir:
        backup = Path(tmpdir) / 'protein_kinetics.csv'
        shutil.copy2(CSV_PATH, backup)

        script = find_and_run_script()
        original_reference = reference_analysis(backup)

        try:
            write_alternate_dataset(CSV_PATH)
            alternate_reference = reference_analysis(CSV_PATH)
            alternate = run_selected_script(script)

            for key in ('mean_k_UI', 'mean_k_IB', 'p_k_UI_greater_k_IB'):
                assert isinstance(alternate.get(key), (int, float)) and not isinstance(alternate.get(key), bool)
                assert math.isfinite(float(alternate[key]))
            assert isinstance(alternate.get('reject_null'), bool)
            assert abs(float(alternate['mean_k_UI']) - alternate_reference['mean_k_UI']) < 0.30
            assert abs(float(alternate['mean_k_IB']) - alternate_reference['mean_k_IB']) < 0.30
            assert abs(float(alternate['p_k_UI_greater_k_IB']) - alternate_reference['p_k_UI_greater_k_IB']) < 0.10
            assert alternate['mean_k_UI'] < alternate['mean_k_IB'], (
                'The analysis did not respond to a dataset where k_UI is slower than k_IB.'
            )
            assert alternate['reject_null'] is (alternate['p_k_UI_greater_k_IB'] > 0.95)
        finally:
            shutil.copy2(backup, CSV_PATH)

        final_data = run_selected_script(script)
        validate_original_assertions(final_data)
        assert abs(float(final_data['mean_k_UI']) - original_reference['mean_k_UI']) < 0.20
        assert abs(float(final_data['mean_k_IB']) - original_reference['mean_k_IB']) < 0.20
        assert abs(float(final_data['p_k_UI_greater_k_IB']) - original_reference['p_k_UI_greater_k_IB']) < 0.08
        assert final_data['reject_null'] is (final_data['p_k_UI_greater_k_IB'] > 0.95)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
