#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import stat
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

HOME = Path('/home/user')
RESULTS = HOME / 'sim_results.csv'
ORACLE_CLEAN = HOME / 'oracle_clean.csv'
SOURCE = HOME / 'fast_sim.c'
WORKFLOW = HOME / 'workflow.sh'
FAST_SIM = HOME / 'fast_sim'
STATE = {}


def read_strict_csv(path, expected_header, expected_rows):
    with open(path, newline='') as f:
        rows = list(csv.reader(f))
    assert rows, f'{path} is empty'
    assert rows[0] == expected_header, f'{path} must have header {expected_header}, got {rows[0]}'
    assert len(rows) == expected_rows + 1, f'{path} must contain exactly {expected_rows} data rows'
    assert all(len(row) == len(expected_header) for row in rows[1:]), f'{path} has an incorrect number of columns'
    values = np.array([[float(value) for value in row] for row in rows[1:]], dtype=float)
    assert np.isfinite(values).all(), f'{path} contains non-finite values'
    return values


def generate_truth():
    t_val = 0.0
    x_val = 2.0
    v_val = 0.0
    dt = 0.01
    omega = 1.5
    gamma = 0.2
    alpha = 0.1
    truth = []

    for _ in range(2001):
        truth.append((t_val, x_val, v_val))

        k1_x = v_val
        k1_v = -gamma*v_val - omega*omega*x_val - alpha*x_val**3

        x2 = x_val + 0.5*dt*k1_x
        v2 = v_val + 0.5*dt*k1_v
        k2_x = v2
        k2_v = -gamma*v2 - omega*omega*x2 - alpha*x2**3

        x3 = x_val + 0.5*dt*k2_x
        v3 = v_val + 0.5*dt*k2_v
        k3_x = v3
        k3_v = -gamma*v3 - omega*omega*x3 - alpha*x3**3

        x4 = x_val + dt*k3_x
        v4 = v_val + dt*k3_v
        k4_x = v4
        k4_v = -gamma*v4 - omega*omega*x4 - alpha*x4**3

        x_val += (dt/6.0)*(k1_x + 2*k2_x + 2*k3_x + k4_x)
        v_val += (dt/6.0)*(k1_v + 2*k2_v + 2*k3_v + k4_v)
        t_val += dt

    return np.array(truth)


@pytest.fixture(scope='session', autouse=True)
def execute_required_artifacts():
    for path in (SOURCE, WORKFLOW):
        assert path.exists(), f'{path} does not exist'
        assert not path.is_symlink(), f'{path} must not be a symlink'
        assert stat.S_ISREG(path.stat().st_mode), f'{path} must be a regular file'
        assert path.stat().st_size > 0, f'{path} is empty'

    for path in (RESULTS, ORACLE_CLEAN, FAST_SIM):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

    run = subprocess.run(
        ['/bin/bash', str(WORKFLOW)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    STATE['workflow_output'] = run.stdout
    assert run.returncode == 0, f'workflow.sh failed:\n{run.stdout}'
    assert RESULTS.is_file(), 'workflow.sh did not create sim_results.csv'
    assert ORACLE_CLEAN.is_file(), 'workflow.sh did not create oracle_clean.csv'
    assert FAST_SIM.is_file(), 'workflow.sh did not create fast_sim'
    assert os.access(FAST_SIM, os.X_OK), 'fast_sim is not executable'
    with open(FAST_SIM, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'workflow.sh did not produce a compiled executable fast_sim'

    # Compile the submitted C source independently with the required options and
    # execute that compiled artifact, so canned CSV files cannot satisfy the task.
    checked_binary = Path('/tmp/checked_fast_sim')
    try:
        checked_binary.unlink()
    except FileNotFoundError:
        pass
    compile_run = subprocess.run(
        ['gcc', '-O2', str(SOURCE), '-o', str(checked_binary), '-lm'],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert compile_run.returncode == 0, f'fast_sim.c does not compile with -O2 -lm:\n{compile_run.stdout}'
    RESULTS.unlink()
    sim_run = subprocess.run(
        [str(checked_binary)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert sim_run.returncode == 0, f'independently compiled fast_sim.c failed:\n{sim_run.stdout}'
    assert RESULTS.is_file(), 'the independently compiled fast_sim.c did not create sim_results.csv'


def test_sim_results_exists_and_format():
    assert os.path.isfile(RESULTS), f'File {RESULTS} does not exist.'

    df = pd.read_csv(RESULTS)
    assert 't' in df.columns, "Column 't' missing from sim_results.csv"
    assert 'x' in df.columns, "Column 'x' missing from sim_results.csv"
    assert 'v' in df.columns, "Column 'v' missing from sim_results.csv"
    assert len(df) >= 2001, f'Expected at least 2001 rows, got {len(df)}'

    values = read_strict_csv(RESULTS, ['t', 'x', 'v'], 2001)
    assert np.allclose(values[:, 0], np.arange(2001) * 0.01, rtol=0, atol=1e-9), 't values are not exactly the required 0.01 grid from 0 to 20'


def test_sim_results_accuracy():
    assert os.path.isfile(RESULTS), f'File {RESULTS} does not exist.'
    df = pd.read_csv(RESULTS)
    truth = generate_truth()

    truth_x = truth[:, 1]
    agent_x = df['x'].values[:2001]
    mse = np.mean((truth_x - agent_x)**2)
    rmse = np.sqrt(mse)
    threshold = 1e-4
    assert rmse < threshold, f'RMSE {rmse} is not less than threshold {threshold}'

    values = read_strict_csv(RESULTS, ['t', 'x', 'v'], 2001)
    v_rmse = np.sqrt(np.mean((truth[:, 2] - values[:, 2])**2))
    assert v_rmse < threshold, f'velocity RMSE {v_rmse} is not less than threshold {threshold}'


def test_oracle_clean_is_actual_parsed_oracle_output():
    values = read_strict_csv(ORACLE_CLEAN, ['t', 'x'], 2001)
    oracle_run = subprocess.run(
        ['/app/oracle_sim'], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=True, timeout=30
    )
    pattern = re.compile(r'^Time:\s*([-+0-9.eE]+)\s*\|\s*Position:\s*([-+0-9.eE]+)\s*\|')
    expected = []
    for line in oracle_run.stdout.splitlines():
        match = pattern.match(line.strip())
        if match:
            expected.append((float(match.group(1)), float(match.group(2))))
    expected = np.array(expected)
    assert expected.shape == (2001, 2), 'Could not derive 2001 oracle samples'
    assert np.allclose(values[:, 0], expected[:, 0], rtol=0, atol=1e-9), 'oracle_clean.csv has incorrect t values'
    assert np.allclose(values[:, 1], expected[:, 1], rtol=0, atol=5.1e-7), 'oracle_clean.csv does not contain the oracle x values'


def test_workflow_prints_maximum_difference():
    oracle_values = read_strict_csv(ORACLE_CLEAN, ['t', 'x'], 2001)
    result_values = read_strict_csv(RESULTS, ['t', 'x', 'v'], 2001)
    expected_max = float(np.max(np.abs(oracle_values[:, 1] - result_values[:, 1])))

    number = r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?'
    candidates = []
    for line in STATE['workflow_output'].splitlines():
        stripped = line.strip()
        lower = stripped.lower()
        if re.fullmatch(number, stripped) or ('max' in lower and 'diff' in lower):
            candidates.extend(float(x) for x in re.findall(number, stripped))
    assert candidates, f'workflow.sh did not print a maximum-difference value:\n{STATE["workflow_output"]}'
    assert any(math.isfinite(x) and abs(x - expected_max) <= 1e-6 for x in candidates), \
        f'workflow output does not report the computed maximum difference {expected_max}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
