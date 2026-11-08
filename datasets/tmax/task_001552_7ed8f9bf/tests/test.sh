#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SITE_EOF' > /tmp/sitecustomize.py
import json
import os
from pathlib import Path

probe_dir = Path('/tmp/mpi_probe')
probe_dir.mkdir(parents=True, exist_ok=True)
rank = os.environ.get('OMPI_COMM_WORLD_RANK', 'none')
pid = os.getpid()
(probe_dir / f'process_{rank}_{pid}').touch()

try:
    import scipy.stats

    _original_wasserstein = scipy.stats.wasserstein_distance

    def _recording_wasserstein(u_values, v_values, u_weights=None, v_weights=None):
        def serial(value):
            if value is None:
                return None
            try:
                return value.tolist()
            except AttributeError:
                return list(value)

        record = {
            'rank': os.environ.get('OMPI_COMM_WORLD_RANK'),
            'u_values': serial(u_values),
            'v_values': serial(v_values),
            'u_weights': serial(u_weights),
            'v_weights': serial(v_weights),
        }
        with open(probe_dir / f'wasserstein_{rank}_{pid}.jsonl', 'a') as f:
            f.write(json.dumps(record) + '\n')
        return _original_wasserstein(u_values, v_values, u_weights, v_weights)

    scipy.stats.wasserstein_distance = _recording_wasserstein
except Exception:
    pass
SITE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import math
import os
import shutil
import stat
import subprocess

import numpy as np
import pytest
from scipy.stats import wasserstein_distance

SCRIPT_PATH = '/home/user/diffusion_mpi.py'
RESULTS_PATH = '/home/user/results.csv'
PROBE_DIR = '/tmp/mpi_probe'


def reference_run(alpha):
    x = np.linspace(0.0, 1.0, 50)
    initial = np.zeros(50, dtype=float)
    initial[20:30] = 1.0
    u = initial.copy()
    coefficient = alpha * 0.001 / ((1.0 / 49.0) ** 2)

    for _ in range(100):
        new_u = u.copy()
        new_u[1:-1] = u[1:-1] + coefficient * (u[2:] - 2.0 * u[1:-1] + u[:-2])
        new_u[0] = 0.0
        new_u[-1] = 0.0
        u = new_u
        if np.isnan(u).any() or np.max(np.abs(u)) > 100.0:
            return x, initial / initial.sum(), None, -1.0

    final = u / u.sum()
    initial = initial / initial.sum()
    distance = wasserstein_distance(x, x, u_weights=initial, v_weights=final)
    return x, initial, final, distance


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f'Expected MPI script {SCRIPT_PATH} does not exist.'
    mode = os.stat(SCRIPT_PATH, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f'Expected {SCRIPT_PATH} to be a regular file.'
    assert os.path.getsize(SCRIPT_PATH) > 0, f'Expected {SCRIPT_PATH} to be non-empty.'

    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    compile(source, SCRIPT_PATH, 'exec')
    lowered = source.lower()
    assert 'mpi4py' in lowered, 'The submitted script does not import mpi4py.'
    assert 'comm_world' in lowered, 'The submitted script does not use MPI.COMM_WORLD.'
    assert ('get_rank' in lowered or '.rank' in lowered), 'The submitted script does not obtain its MPI rank.'
    assert 'gather' in lowered, 'The submitted script does not gather rank results.'

    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    shutil.rmtree(PROBE_DIR, ignore_errors=True)
    os.makedirs(PROBE_DIR, exist_ok=True)

    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp' + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['OMPI_ALLOW_RUN_AS_ROOT'] = '1'
    env['OMPI_ALLOW_RUN_AS_ROOT_CONFIRM'] = '1'

    completed = subprocess.run(
        ['mpirun', '--allow-run-as-root', '-np', '4', 'python3', SCRIPT_PATH],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=90,
    )
    assert completed.returncode == 0, 'MPI script failed:\n' + completed.stdout[-4000:]
    assert os.path.isfile(RESULTS_PATH), 'The executed MPI script did not create results.csv.'


def test_results_csv_exists():
    """Check if the results.csv file was created."""
    assert os.path.isfile(RESULTS_PATH), f'Expected results file {RESULTS_PATH} does not exist.'


def test_results_csv_content():
    """Validate the contents of results.csv against expected diffusion results."""
    assert os.path.isfile(RESULTS_PATH), f'Expected results file {RESULTS_PATH} does not exist.'

    expected = {
        0.1: 0.05260840134447475,
        0.2: 0.07629088689726887,
        0.25: -1.0,
        0.3: -1.0,
    }

    actual_results = {}
    rows = []
    with open(RESULTS_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            assert len(row) == 2, f'Expected 2 columns in CSV row, found {len(row)}: {row}'
            try:
                alpha = float(row[0])
                dist = float(row[1])
            except ValueError:
                assert False, f'Could not parse row values as floats: {row}'
            rows.append((alpha, dist))
            actual_results[alpha] = dist

    assert len(rows) == 4, f'Expected exactly 4 rows in CSV, found {len(rows)}'
    assert len(actual_results) == 4, f'Expected exactly 4 rows in CSV, found {len(actual_results)}'
    assert [alpha for alpha, _ in rows] == [0.1, 0.2, 0.25, 0.3], 'CSV rows are not sorted ascending by alpha.'

    for alpha, expected_dist in expected.items():
        assert actual_results.get(alpha) is not None, f'Missing result for alpha = {alpha}'
        actual_dist = actual_results[alpha]
        assert math.isclose(actual_dist, expected_dist, rel_tol=1e-5), \
            f'Incorrect distance for alpha={alpha}. Expected {expected_dist}, got {actual_dist}'


def test_script_exists():
    """Check if the Python script was created at the expected path."""
    assert os.path.isfile(SCRIPT_PATH), f'Expected MPI script {SCRIPT_PATH} does not exist.'


def test_all_four_mpi_ranks_executed():
    ranks = set()
    for path in glob.glob(PROBE_DIR + '/process_*'):
        parts = os.path.basename(path).split('_')
        if len(parts) >= 3 and parts[1].isdigit():
            ranks.add(int(parts[1]))
    assert ranks == {0, 1, 2, 3}, f'Expected execution on MPI ranks 0-3, observed ranks {sorted(ranks)}.'


def test_wasserstein_inputs_are_ftcs_profiles():
    records = []
    for path in glob.glob(PROBE_DIR + '/wasserstein_*.jsonl'):
        with open(path) as f:
            records.extend(json.loads(line) for line in f if line.strip())

    assert len(records) == 2, 'Wasserstein distance must be computed exactly for the two stable runs.'
    by_rank = {int(record['rank']): record for record in records}
    assert set(by_rank) == {0, 1}, 'Only ranks 0 and 1 should compute Wasserstein distances.'

    for rank, alpha in ((0, 0.1), (1, 0.2)):
        x, initial, final, expected_distance = reference_run(alpha)
        assert final is not None
        record = by_rank[rank]
        u_values = np.asarray(record['u_values'], dtype=float)
        v_values = np.asarray(record['v_values'], dtype=float)
        u_weights = np.asarray(record['u_weights'], dtype=float)
        v_weights = np.asarray(record['v_weights'], dtype=float)

        assert u_values.shape == (50,) and np.allclose(u_values, x, rtol=0, atol=1e-12)
        assert v_values.shape == (50,) and np.allclose(v_values, x, rtol=0, atol=1e-12)
        normal_order = np.allclose(u_weights, initial, rtol=1e-9, atol=1e-12) and np.allclose(v_weights, final, rtol=1e-9, atol=1e-12)
        reverse_order = np.allclose(v_weights, initial, rtol=1e-9, atol=1e-12) and np.allclose(u_weights, final, rtol=1e-9, atol=1e-12)
        assert normal_order or reverse_order, f'Rank {rank} did not pass the normalized FTCS profile to Wasserstein.'
        assert math.isclose(expected_distance, {0: 0.05260840134447475, 1: 0.07629088689726887}[rank], rel_tol=1e-12)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
