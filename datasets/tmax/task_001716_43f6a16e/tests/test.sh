#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import shutil
import subprocess
import sys
import tempfile
import numpy as np
import pytest

PREDICTIONS_PATH = '/home/user/predictions.csv'
EVAL_DATA_PATH = '/home/user/eval_data.csv'
ORACLE_PATH = '/app/oracle_engine'
SOLVER_PATH = '/home/user/py_engine/solver.py'
REPO_PATH = '/home/user/py_engine'


def parse_floats(text, source):
    try:
        values = np.array([float(x) for x in text.strip().split('\n') if x.strip()], dtype=float)
    except ValueError:
        pytest.fail(f'Failed to parse {source} as one floating-point number per line.')
    assert len(values) > 0, f'{source} produced no values.'
    assert np.all(np.isfinite(values)), f'{source} contains non-finite values.'
    return values


def test_predictions_mse():
    assert os.path.exists(PREDICTIONS_PATH), f'Agent output file {PREDICTIONS_PATH} does not exist. Did you save the predictions?'
    assert os.path.exists(EVAL_DATA_PATH), f'Evaluation data {EVAL_DATA_PATH} is missing.'
    assert os.path.exists(ORACLE_PATH), f'Oracle engine {ORACLE_PATH} is missing.'

    try:
        oracle_out = subprocess.check_output([ORACLE_PATH, EVAL_DATA_PATH], text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Failed to run oracle engine: {e}')

    expected = parse_floats(oracle_out, 'oracle output')
    try:
        with open(PREDICTIONS_PATH, 'r') as f:
            predicted = parse_floats(f.read(), PREDICTIONS_PATH)
    except OSError as e:
        pytest.fail(f'Failed to read {PREDICTIONS_PATH}: {e}')

    assert len(expected) == len(predicted), f'Length mismatch: expected {len(expected)} predictions, got {len(predicted)}.'
    mse = np.mean((expected - predicted) ** 2)
    assert mse < 1e-10, f'Output MSE {mse} is above threshold 1e-10. Convergence/precision issue not fully fixed.'


def write_case(path, vec, adj):
    with open(path, 'w') as f:
        f.write(','.join(format(float(x), '.17g') for x in vec) + '\n')
        for row in adj:
            f.write(','.join(format(float(x), '.17g') for x in row) + '\n')


def demote_to_user():
    account = pwd.getpwnam('user')
    os.initgroups(account.pw_name, account.pw_gid)
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_repaired_solver_on_independent_inputs():
    assert os.path.isfile(SOLVER_PATH), f'Repaired solver {SOLVER_PATH} is missing or is not a regular file.'
    assert not os.path.islink(SOLVER_PATH), 'solver.py must be an actual repaired source file, not a symlink.'
    assert os.path.exists(ORACLE_PATH), f'Oracle engine {ORACLE_PATH} is missing.'

    with open(SOLVER_PATH, 'rb') as f:
        submitted = f.read()
    bad_version = subprocess.check_output(['git', 'show', 'v2.0:solver.py'], cwd=REPO_PATH)
    good_reference = subprocess.check_output(['git', 'show', 'v1.0:solver.py'], cwd=REPO_PATH)
    assert submitted != bad_version, 'solver.py is still byte-identical to the known-bad v2.0 implementation.'
    assert submitted != good_reference, 'solver.py must repair the current codebase rather than copy the shipped known-good reference verbatim.'

    workdir = tempfile.mkdtemp(prefix='engine_verifier_', dir='/tmp')
    os.chmod(workdir, 0o755)
    cases = []
    try:
        # This boundary case distinguishes the float32-truncated convergence
        # check from the required double-precision check.
        cases.append((np.array([2e-12]), np.array([[0.5]])))

        rng = np.random.default_rng(731942)
        for n, scale in ((3, 0.61), (7, 0.83)):
            vec = rng.random(n)
            adj = rng.random((n, n))
            adj = adj / adj.sum(axis=0, keepdims=True)
            adj *= scale
            cases.append((vec, adj))

        paths = []
        expected_outputs = []
        for index, (vec, adj) in enumerate(cases):
            path = os.path.join(workdir, f'case_{index}.csv')
            write_case(path, vec, adj)
            os.chmod(path, 0o644)
            paths.append(path)
            try:
                oracle_out = subprocess.check_output([ORACLE_PATH, path], text=True, timeout=15)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                pytest.fail(f'Oracle failed on verifier case {index}: {e}')
            expected_outputs.append(parse_floats(oracle_out, f'oracle case {index}'))

        # Execute the submitted Python implementation while the oracle is
        # inaccessible to the unprivileged solver process. This verifies the
        # implementation rather than an oracle-forwarding wrapper.
        hidden_dir = tempfile.mkdtemp(prefix='engine_oracle_', dir='/root')
        os.chmod(hidden_dir, 0o700)
        hidden_oracle = os.path.join(hidden_dir, 'oracle_engine')
        shutil.move(ORACLE_PATH, hidden_oracle)
        try:
            for index, (path, expected) in enumerate(zip(paths, expected_outputs)):
                try:
                    result = subprocess.run(
                        [sys.executable, SOLVER_PATH, path],
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=20,
                        check=False,
                        preexec_fn=demote_to_user,
                    )
                except subprocess.TimeoutExpired:
                    pytest.fail(f'solver.py timed out on verifier case {index}.')
                assert result.returncode == 0, f'solver.py failed on verifier case {index}: {result.stderr}'
                actual = parse_floats(result.stdout, f'solver output for case {index}')
                assert len(actual) == len(expected), f'Case {index}: expected {len(expected)} values, got {len(actual)}.'
                assert np.allclose(actual, expected, rtol=6e-6, atol=2e-17), (
                    f'Case {index}: repaired solver does not match the oracle. '
                    f'Expected {expected!r}, got {actual!r}.'
                )
        finally:
            if os.path.exists(hidden_oracle):
                shutil.move(hidden_oracle, ORACLE_PATH)
            shutil.rmtree(hidden_dir, ignore_errors=True)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
