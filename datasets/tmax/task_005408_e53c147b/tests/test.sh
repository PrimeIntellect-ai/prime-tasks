#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import pathlib
import shutil
import subprocess
import sys

import numpy as np
from scipy.sparse import csc_matrix, lil_matrix
from scipy.sparse.linalg import factorized
from scipy.stats import wasserstein_distance

HOME = pathlib.Path('/home/user')
RESULTS = HOME / 'results.json'
OBSERVED = HOME / 'observed_variant.csv'

BASE_X = np.array([i / 10.0 for i in range(11)], dtype=float)
BASE_U = np.array([0.01, 0.05, 0.15, 0.35, 0.45, 0.45, 0.35, 0.15, 0.05, 0.01, 0.005], dtype=float)
MUTANT_U = np.zeros(11, dtype=float)
MUTANT_U[2] = 1.0


def write_observed(values):
    with open(OBSERVED, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['x', 'observed_u'])
        writer.writerows(zip(BASE_X, values))


def solve_reference(nx):
    D = 0.01
    r = 0.5
    dt = 0.002
    dx = 1.0 / (nx - 1)
    x = np.linspace(0.0, 1.0, nx)
    u = np.exp(-100.0 * (x - 0.5) ** 2)

    # Backward Euler for diffusion and explicit Euler for the reaction term.
    # Ghost-point Neumann conditions give doubled boundary off-diagonals.
    alpha = D * dt / (dx * dx)
    A = lil_matrix((nx, nx), dtype=float)
    A.setdiag(1.0 + 2.0 * alpha)
    for i in range(1, nx - 1):
        A[i, i - 1] = -alpha
        A[i, i + 1] = -alpha
    A[0, 1] = -2.0 * alpha
    A[nx - 1, nx - 2] = -2.0 * alpha
    linear_solve = factorized(csc_matrix(A))

    for _ in range(1000):
        rhs = u + dt * r * u * (1.0 - u)
        u = np.asarray(linear_solve(rhs), dtype=float)
    return x, u


X_COARSE, U_COARSE = solve_reference(51)
X_FINE, U_FINE = solve_reference(101)
EXPECTED_CONV = float(np.max(np.abs(U_COARSE - U_FINE[::2])))


def expected_wasserstein(observed_u):
    observed_u = np.asarray(observed_u, dtype=float)
    return float(wasserstein_distance(
        X_FINE,
        BASE_X,
        u_weights=U_FINE / U_FINE.sum(),
        v_weights=observed_u / observed_u.sum(),
    ))


EXPECTED_BASE_W = expected_wasserstein(BASE_U)
EXPECTED_MUTANT_W = expected_wasserstein(MUTANT_U)


def load_results():
    assert RESULTS.exists(), f'File {RESULTS} is missing. The script must generate this file.'
    assert RESULTS.is_file(), f'{RESULTS} is not a file.'
    try:
        with open(RESULTS, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {RESULTS} is not a valid JSON file: {exc}')

    assert 'convergence_error' in data, "Key 'convergence_error' is missing from results.json."
    assert 'wasserstein_distance' in data, "Key 'wasserstein_distance' is missing from results.json."
    conv = data['convergence_error']
    wass = data['wasserstein_distance']
    assert isinstance(conv, (int, float)), "'convergence_error' must be a number."
    assert isinstance(wass, (int, float)), "'wasserstein_distance' must be a number."
    assert math.isfinite(float(conv)), "'convergence_error' must be finite."
    assert math.isfinite(float(wass)), "'wasserstein_distance' must be finite."
    return data, float(conv), float(wass)


def source_candidates():
    excluded = {RESULTS.resolve(), OBSERVED.resolve()}
    suffixes = {'.py', '.sh', '.bash', '.r', '.R', '.jl', '.js', '.pl', '.rb'}
    found = []
    for path in HOME.rglob('*'):
        try:
            if not path.is_file() or path.resolve() in excluded or path.stat().st_size > 2_000_000:
                continue
        except OSError:
            continue
        if any(part.startswith('.') for part in path.relative_to(HOME).parts):
            continue
        try:
            first = path.open('rb').read(256)
        except OSError:
            continue
        if path.suffix in suffixes or first.startswith(b'#!'):
            try:
                text = path.read_text(errors='ignore').lower()
            except OSError:
                text = ''
            score = sum(token in text for token in ('fisher', 'wasserstein', 'sparse', '0.002', '1000', 'results.json'))
            found.append((-score, len(path.parts), str(path), path))
    found.sort()
    return [item[3] for item in found]


def command_for(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return [sys.executable, str(path)]
    if suffix in ('.sh', '.bash'):
        return ['bash', str(path)]
    runners = {'.r': 'Rscript', '.jl': 'julia', '.js': 'node', '.pl': 'perl', '.rb': 'ruby'}
    if suffix in runners and shutil.which(runners[suffix]):
        return [runners[suffix], str(path)]
    if os.access(path, os.X_OK):
        return [str(path)]
    return None


def execute(path, observed_values):
    write_observed(observed_values)
    try:
        RESULTS.unlink()
    except FileNotFoundError:
        pass
    cmd = command_for(path)
    if cmd is None:
        raise AssertionError(f'Cannot execute candidate script {path}')
    completed = subprocess.run(
        cmd,
        cwd=str(HOME),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
        env={**os.environ, 'HOME': str(HOME)},
    )
    assert completed.returncode == 0, f'{path} exited with status {completed.returncode}:\n{completed.stdout[-3000:]}'
    return load_results()


def close(actual, expected, tolerance=0.005):
    return abs(actual - expected) <= tolerance


def main():
    candidates = source_candidates()
    assert candidates, 'No executable solver script was found under /home/user.'

    selected = None
    diagnostics = []
    for candidate in candidates:
        try:
            _, mutant_conv, mutant_wass = execute(candidate, MUTANT_U)
            assert close(mutant_conv, EXPECTED_CONV), (
                f'convergence error {mutant_conv} does not match the independently computed value {EXPECTED_CONV}'
            )
            assert close(mutant_wass, EXPECTED_MUTANT_W), (
                f'Wasserstein distance {mutant_wass} does not respond correctly to changed observed data; '
                f'expected {EXPECTED_MUTANT_W}'
            )

            _, base_conv, base_wass = execute(candidate, BASE_U)
            assert close(base_conv, EXPECTED_CONV), (
                f'convergence error {base_conv} does not match the independently computed value {EXPECTED_CONV}'
            )
            assert close(base_wass, EXPECTED_BASE_W), (
                f'Wasserstein distance {base_wass} does not match the independently computed value {EXPECTED_BASE_W}'
            )
            selected = candidate
            break
        except Exception as exc:
            diagnostics.append(f'{candidate}: {exc}')

    assert selected is not None, 'No submitted script produced correct recomputed results when executed. ' + ' | '.join(diagnostics[-5:])

    # Inspect the submitted source tree for the requested sparse system and
    # decomposition/linear-solve implementation, allowing modular scripts.
    corpus_parts = []
    for path in candidates:
        try:
            corpus_parts.append(path.read_text(errors='ignore').lower())
        except OSError:
            pass
    corpus = '\n'.join(corpus_parts)
    sparse_markers = ('scipy.sparse', 'csr_matrix', 'csc_matrix', 'lil_matrix', 'spdiags', 'diags(', 'sparse matrix', 'sparsematrix')
    decomposition_markers = ('splu', 'spsolve', 'factorized', 'lu_factor', 'lu_solve', 'cholesky', 'cho_factor', 'solve_banded', 'thomas', 'decomposition')
    assert any(marker in corpus for marker in sparse_markers), 'Solver code does not construct a sparse linear system.'
    assert any(marker in corpus for marker in decomposition_markers), 'Solver code does not use a matrix decomposition or sparse linear solver.'
    assert ('0.002' in corpus or '1000' in corpus), 'Solver code does not show the required 0.002 time step or 1000 time steps.'
    grid_ok = (('51' in corpus and '101' in corpus) or ('50' in corpus and '100' in corpus))
    assert grid_ok, 'Solver code does not show both required spatial resolutions.'

    # Preserve the original verifier's assertions on the final, baseline run.
    _, conv_err, wass_dist = load_results()
    assert 0.0 < conv_err < 0.05, f"'convergence_error' ({conv_err}) is outside the expected range (0.0, 0.05)."
    assert 0.0 <= wass_dist < 0.1, f"'wasserstein_distance' ({wass_dist}) is outside the expected range [0.0, 0.1)."


if __name__ == '__main__':
    try:
        main()
    finally:
        write_observed(BASE_U)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
