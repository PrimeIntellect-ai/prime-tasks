#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
from pathlib import Path

import h5py
import numpy as np
import pytest

OUTPUT = Path('/home/user/kappa_estimate.txt')
ALIGNMENT = Path('/app/alignments.h5')
EXECUTABLE = Path('/tmp/submission_mcmc')


def find_and_compile_source():
    candidates = [p for p in Path('/home/user').rglob('*.c') if p.is_file()]
    assert candidates, 'No C source file was found under /home/user.'

    def score(path):
        name = path.name.lower()
        return (0 if name == 'mcmc_kappa.c' else 1,
                0 if ('mcmc' in name or 'kappa' in name) else 1,
                str(path))

    errors = []
    for source in sorted(candidates, key=score):
        assert source.stat().st_size > 0, f'C source file {source} is empty.'
        result = subprocess.run(
            ['h5cc', '-O2', str(source), '-o', str(EXECUTABLE), '-lm'],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        if result.returncode == 0:
            with open(EXECUTABLE, 'rb') as f:
                assert f.read(4) == b'\x7fELF', 'Compiled artifact is not an ELF executable.'
            return source
        errors.append(f'{source}: {result.stderr[-1000:]}')

    pytest.fail('No submitted C source compiled successfully with HDF5.\n' + '\n'.join(errors))


def make_alignment(path, nts, ntv):
    assert nts + ntv <= 99 * 50
    seqs = np.zeros((100, 50), dtype=np.int64)
    kinds = np.array([1] * nts + [2] * ntv, dtype=np.int8)
    np.random.default_rng(secrets.randbits(128)).shuffle(kinds)
    event = 0
    for row in range(1, 100):
        seqs[row] = seqs[row - 1]
        for col in range(50):
            if event >= len(kinds):
                break
            old = int(seqs[row, col])
            if kinds[event] == 1:
                seqs[row, col] = {0: 2, 2: 0, 1: 3, 3: 1}[old]
            else:
                seqs[row, col] = {0: 1, 1: 0, 2: 1, 3: 0}[old]
            event += 1
    assert event == len(kinds)
    with h5py.File(path, 'w') as h5:
        h5.create_dataset('/sequences', data=seqs)


def count_changes(path):
    with h5py.File(path, 'r') as h5:
        seqs = np.asarray(h5['/sequences'])
    assert seqs.shape == (100, 50)
    a, b = seqs[:-1], seqs[1:]
    changed = a != b
    transitions = changed & ((((a == 0) & (b == 2)) | ((a == 2) & (b == 0))) |
                             (((a == 1) & (b == 3)) | ((a == 3) & (b == 1))))
    return int(transitions.sum()), int((changed & ~transitions).sum())


def posterior_mean(nts, ntv):
    grid = np.linspace(1.0, 5.0, 250001)
    logp = nts * np.log(grid / (grid + 2.0)) + 2 * ntv * np.log(1.0 / (grid + 2.0))
    weights = np.exp(logp - logp.max())
    return float(np.trapz(grid * weights, grid) / np.trapz(weights, grid))


def run_submission():
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    result = subprocess.run(
        [str(EXECUTABLE)], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45
    )
    assert result.returncode == 0, (
        f'Compiled program exited with status {result.returncode}.\n'
        f'stdout: {result.stdout[-2000:]}\nstderr: {result.stderr[-2000:]}'
    )
    assert OUTPUT.exists(), f'Output file {OUTPUT} does not exist.'
    assert OUTPUT.is_file(), f'Path {OUTPUT} is not a file.'
    content = OUTPUT.read_text().strip()
    assert content, f'File {OUTPUT} is empty.'
    assert re.fullmatch(r'[+-]?(?:\d+\.\d{3})', content), (
        f'Output must be one finite float rounded to exactly 3 decimal places; got {content!r}.'
    )
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f'Could not parse the content of {OUTPUT} as a float. Content: {content!r}')
    assert np.isfinite(value), 'Estimated kappa must be finite.'
    return value


def assert_estimate(nts, ntv, tolerance=0.05):
    observed_counts = count_changes(ALIGNMENT)
    assert observed_counts == (nts, ntv), (
        f'Internal test alignment has counts {observed_counts}, expected {(nts, ntv)}.'
    )
    estimate = run_submission()
    expected = posterior_mean(nts, ntv)
    assert abs(estimate - expected) <= tolerance, (
        f'Estimated kappa {estimate:.3f} is inconsistent with the posterior mean '
        f'{expected:.3f} for N_ts={nts}, N_tv={ntv}.'
    )
    return estimate


def test_c_program_processes_hdf5_and_runs_sampler():
    find_and_compile_source()
    backup = Path('/tmp/original_alignments.h5')
    shutil.copy2(ALIGNMENT, backup)
    try:
        # Preserve the original verifier's accuracy assertion on a ratio-2 case,
        # while also checking against the posterior mean derived from its counts.
        make_alignment(ALIGNMENT, 240, 120)
        estimate = assert_estimate(240, 120)
        theoretical_kappa = 2.000
        error = abs(estimate - theoretical_kappa)
        threshold = 0.05
        assert error <= threshold, (
            f'Estimated kappa {estimate:.3f} is too far from the theoretical mode '
            f'{theoretical_kappa:.3f}. Absolute error: {error:.4f} '
            f'(Threshold: <= {threshold})'
        )

        # A verifier-time randomized case prevents a constant-output solution.
        if secrets.randbelow(2) == 0:
            ntv = 80
            nts = 110 + secrets.randbelow(21)
        else:
            ntv = 80
            nts = 240 + secrets.randbelow(31)
        make_alignment(ALIGNMENT, nts, ntv)
        assert_estimate(nts, ntv)

        # Finally run on the actual task data. This leaves the required output
        # corresponding to /app/alignments.h5, whose real counts are 99 and 0.
        shutil.copy2(backup, ALIGNMENT)
        nts, ntv = count_changes(ALIGNMENT)
        assert_estimate(nts, ntv)
    finally:
        shutil.copy2(backup, ALIGNMENT)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
