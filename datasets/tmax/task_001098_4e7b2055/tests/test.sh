#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

import numpy as np
import pytest
from sklearn.cluster import KMeans

PROJECT = Path('/app/fast-log-cluster')
BINARY = PROJECT / 'fast_log_cluster'
OUTPUT = Path('/home/user/centroids.txt')
DATASET = Path('/app/forensic_logs.txt')


def run(cmd, *, cwd=None, timeout=20, stdout=None):
    return subprocess.run(
        cmd,
        cwd=cwd,
        stdout=stdout if stdout is not None else subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=stdout is None,
        timeout=timeout,
        check=True,
    )


def load_strict_centroids(path, expected_rows, expected_dims):
    lines = Path(path).read_text().splitlines()
    assert len(lines) == expected_rows, f'Expected exactly {expected_rows} lines, got {len(lines)}'
    rows = []
    for line in lines:
        parts = line.split(',')
        assert len(parts) == expected_dims, f'Expected {expected_dims} comma-separated coordinates: {line!r}'
        try:
            row = [float(x) for x in parts]
        except ValueError as exc:
            pytest.fail(f'Invalid centroid line {line!r}: {exc}')
        assert np.isfinite(row).all(), f'Centroid contains a non-finite value: {line!r}'
        rows.append(row)
    return np.asarray(rows, dtype=float)


def sort_centroids(c):
    return c[np.lexsort(c.T[::-1])]


@pytest.fixture(scope='session', autouse=True)
def build_and_run_submission():
    makefile = PROJECT / 'Makefile'
    source = PROJECT / 'src/cluster.cpp'
    assert makefile.is_file(), 'Project Makefile is missing.'
    assert source.is_file(), 'src/cluster.cpp is missing.'

    make_text = makefile.read_text()
    assert 'math_v2' in make_text, 'Makefile does not select vendor/math_v2.'
    assert 'math_v1' not in make_text, 'Makefile still references the obsolete vendor/math_v1.'

    source_text = source.read_text()
    assert 'kmeans' in source_text and 'converged' in source_text, 'cluster.cpp lacks a convergence implementation.'
    assert not re.search(r'old_centroids\s*\[\s*i\s*\]\s*!=\s*centroids\s*\[\s*i\s*\]', source_text), \
        'cluster.cpp still uses the defective exact vector-inequality convergence check.'

    if BINARY.exists() or BINARY.is_symlink():
        BINARY.unlink()

    dry = run(['make', '-B', '-n'], cwd=PROJECT).stdout
    assert 'math_v2' in dry and 'math_v1' not in dry, 'Effective build command does not use math_v2.'
    assert 'src/main.cpp' in dry and 'src/cluster.cpp' in dry, 'Build does not compile the required project sources.'

    run(['make', 'clean'], cwd=PROJECT)
    if BINARY.exists() or BINARY.is_symlink():
        BINARY.unlink()
    run(['make'], cwd=PROJECT, timeout=30)

    assert BINARY.is_file(), 'Build did not produce fast_log_cluster.'
    assert os.access(BINARY, os.X_OK), 'fast_log_cluster is not executable.'
    with BINARY.open('rb') as f:
        assert f.read(4) == b'\x7fELF', 'fast_log_cluster is not a compiled ELF binary.'

    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    with OUTPUT.open('w') as out:
        run([str(BINARY), str(DATASET), '5'], cwd=PROJECT, timeout=10, stdout=out)


def test_centroids_mse():
    output_file = '/home/user/centroids.txt'
    dataset_file = '/app/forensic_logs.txt'

    assert os.path.isfile(output_file), f'Output file {output_file} is missing.'
    assert os.path.isfile(dataset_file), f'Dataset file {dataset_file} is missing.'

    try:
        user_centroids = np.loadtxt(output_file, delimiter=',')
    except Exception as e:
        pytest.fail(f'Failed to parse {output_file} as comma-separated floats: {e}')

    assert user_centroids.shape[0] == 5, f'Expected exactly 5 centroids, got {user_centroids.shape[0]}'
    load_strict_centroids(output_file, 5, 2)

    try:
        try:
            X = np.loadtxt(dataset_file, delimiter=',')
        except ValueError:
            X = np.loadtxt(dataset_file)
    except Exception as e:
        pytest.fail(f'Failed to load dataset {dataset_file}: {e}')

    kmeans = KMeans(n_clusters=5, n_init=10, random_state=42)
    kmeans.fit(X)
    ref_centroids = kmeans.cluster_centers_

    assert user_centroids.shape[1] == ref_centroids.shape[1], \
        f'Dimension mismatch: user centroids have {user_centroids.shape[1]} dims, expected {ref_centroids.shape[1]}'

    user_sorted = sort_centroids(user_centroids)
    ref_sorted = sort_centroids(ref_centroids)
    mse = np.mean((user_sorted - ref_sorted) ** 2)

    threshold = 0.01
    assert mse <= threshold, f'MSE {mse:.6f} exceeds threshold {threshold}. The centroids do not match the expected clusters.'


def test_compiled_tool_uses_euclidean_distance(tmp_path):
    # For these seeds, (0,5) ties under Manhattan distance but is closer to
    # (4,4) under squared Euclidean distance. The globally optimal Euclidean
    # result is therefore unambiguous.
    data = tmp_path / 'distance_case.txt'
    data.write_text('0,0\n4,4\n0,5\n')
    result = run([str(BINARY), str(data), '2'], cwd=PROJECT, timeout=5)
    out = tmp_path / 'distance_centroids.txt'
    out.write_text(result.stdout)
    actual = sort_centroids(load_strict_centroids(out, 2, 2))
    expected = sort_centroids(np.asarray([[0.0, 0.0], [2.0, 4.5]]))
    assert np.allclose(actual, expected, atol=1e-5), \
        f'Compiled tool did not produce Euclidean k-means centroids: {actual}'


def test_compiled_tool_converges_on_unseen_input(tmp_path):
    points = np.asarray([
        [-10.0, -10.0, 1.0], [0.0, 12.0, 5.0], [14.0, -3.0, 9.0],
        [-9.8, -10.2, 1.2], [-10.2, -9.8, 0.8],
        [0.2, 11.8, 5.2], [-0.2, 12.2, 4.8],
        [14.2, -2.8, 9.2], [13.8, -3.2, 8.8],
    ])
    data = tmp_path / 'unseen.txt'
    with data.open('w') as f:
        for row in points:
            f.write(','.join(map(str, row)) + '\n')

    result = run([str(BINARY), str(data), '3'], cwd=PROJECT, timeout=5)
    out = tmp_path / 'unseen_centroids.txt'
    out.write_text(result.stdout)
    actual = sort_centroids(load_strict_centroids(out, 3, 3))
    expected = sort_centroids(np.asarray([
        points[[0, 3, 4]].mean(axis=0),
        points[[1, 5, 6]].mean(axis=0),
        points[[2, 7, 8]].mean(axis=0),
    ]))
    assert np.allclose(actual, expected, atol=1e-5), \
        f'Unexpected centroids for unseen input: {actual}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
