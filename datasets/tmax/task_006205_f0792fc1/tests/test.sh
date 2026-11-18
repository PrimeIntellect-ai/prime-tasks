#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import sys

import pytest

SCRIPT_PATH = '/home/user/process_data.py'
CONFIG_PATH = '/home/user/.config/app_settings.json'
DIAGNOSTIC_PATH = '/home/user/diagnostic.txt'


def compute_golden_values(tolerance=1e-7):
    val = 0
    prev_metric = 0.0
    for i in range(1, 10000):
        term = i * i * i
        val += term
        current_metric = 10000.0 / float(val)
        if abs(current_metric - prev_metric) < tolerance:
            return i, current_metric
        prev_metric = current_metric
    return None, None


def expected_output(tolerance):
    iteration, metric = compute_golden_values(tolerance)
    assert iteration is not None, f'Golden computation did not converge for tolerance {tolerance}'
    return f'Converged at iteration {iteration} to {metric:.8f}'


def assert_script_output(tolerance):
    expected = expected_output(tolerance)
    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f'{SCRIPT_PATH} timed out for tolerance {tolerance}')

    assert result.returncode == 0, (
        f'{SCRIPT_PATH} exited with {result.returncode} for tolerance {tolerance}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert result.stdout == expected + '\n', (
        f'Expected script output {expected!r} for tolerance {tolerance}, '
        f'got {result.stdout!r}. stderr={result.stderr!r}'
    )
    return expected


def test_config_file_exists_and_correct():
    assert os.path.exists(CONFIG_PATH), f'Configuration file missing at {CONFIG_PATH}'

    with open(CONFIG_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {CONFIG_PATH} does not contain valid JSON.')

    assert 'tolerance' in data, f"'tolerance' key missing in {CONFIG_PATH}"
    assert data['tolerance'] == 1e-7, f"Expected tolerance to be 1e-7, got {data['tolerance']}"


def test_diagnostic_report_correct():
    assert os.path.exists(DIAGNOSTIC_PATH), f'Diagnostic report missing at {DIAGNOSTIC_PATH}'

    with open(DIAGNOSTIC_PATH, 'r') as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) == 2, f'Expected exactly 2 lines in {DIAGNOSTIC_PATH}, found {len(lines)}'

    assert lines[0] == CONFIG_PATH, f"Line 1 expected to be '{CONFIG_PATH}', got '{lines[0]}'"

    golden_iteration, golden_metric = compute_golden_values()
    expected = f'Converged at iteration {golden_iteration} to {golden_metric:.8f}'
    assert lines[1] == expected, f"Line 2 expected to be '{expected}', got '{lines[1]}'"


def test_process_data_fixed_and_functional():
    assert os.path.exists(SCRIPT_PATH), f'Script missing at {SCRIPT_PATH}'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a regular file'

    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()

    assert 'np.int64' in content, 'The script does not appear to use np.int64 to fix the overflow bug.'
    assert 'np.int32' not in content, 'The script still contains np.int32 which causes the overflow bug.'

    with open(CONFIG_PATH, 'rb') as f:
        original_config = f.read()

    try:
        # Execute against the required final configuration.
        actual_output = assert_script_output(1e-7)
        with open(DIAGNOSTIC_PATH, 'r') as f:
            diagnostic_lines = f.read().strip().split('\n')
        assert diagnostic_lines[1] == actual_output

        # Exercise convergence beyond the int32 term-overflow point using
        # runtime-selected tolerances whose expected answers are computed here.
        rng = secrets.SystemRandom()
        tolerances = set()
        while len(tolerances) < 3:
            tolerances.add(rng.randint(2, 20) * 1e-12)

        for tolerance in tolerances:
            with open(CONFIG_PATH, 'w') as f:
                json.dump({'tolerance': tolerance}, f)
            assert_script_output(tolerance)
    finally:
        with open(CONFIG_PATH, 'wb') as f:
            f.write(original_config)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
