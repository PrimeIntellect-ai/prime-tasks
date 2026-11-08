#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
from scipy.integrate import solve_ivp
from scipy.optimize import brentq

HOME = Path('/home/user')
RESULTS = HOME / 'optimized_results.csv'
SEQUENCES = HOME / 'sequences.csv'
SIMULATE = HOME / 'simulate.py'


def read_results(path):
    parsed = {}
    with open(path, newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, 'optimized_results.csv is empty.'
        assert header == ['SeqID', 'Optimal_d'], (
            "Incorrect header in optimized_results.csv. Expected "
            f"['SeqID', 'Optimal_d'], got {header}"
        )
        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f'Row {row} does not have exactly 2 columns.'
            seq_id, optimal_d = row
            try:
                parsed[seq_id] = float(optimal_d)
            except ValueError:
                pytest.fail(f"Could not parse Optimal_d value '{optimal_d}' for {seq_id} as a float.")
    return parsed


def test_01_optimized_results_exists():
    assert RESULTS.is_file(), f'Expected output file {RESULTS} does not exist.'


def test_02_optimized_results_content():
    assert RESULTS.is_file(), f'Expected output file {RESULTS} does not exist.'
    expected_results = {
        'seq_1': 1.7361,
        'seq_2': 2.2222,
        'seq_3': 1.3333,
        'seq_4': 1.2963,
        'seq_5': 4.4000,
    }
    parsed_results = read_results(RESULTS)
    assert len(parsed_results) == len(expected_results), (
        f'Expected {len(expected_results)} results, found {len(parsed_results)}.'
    )
    for seq_id, expected_d in expected_results.items():
        assert seq_id in parsed_results, f'Missing result for {seq_id}.'
        actual_d = parsed_results[seq_id]
        assert abs(actual_d - expected_d) < 1e-3, (
            f'Incorrect Optimal_d for {seq_id}. Expected {expected_d}, got {actual_d}.'
        )


def final_m(k_syn, d):
    sol = solve_ivp(
        lambda t, y: [k_syn - d * y[0] ** 2],
        (0.0, 100.0),
        [0.0],
        method='Radau',
        rtol=1e-10,
        atol=1e-12,
    )
    assert sol.success
    return float(sol.y[0, -1])


def pipeline_candidates():
    parallel_pattern = re.compile(
        r'multiprocessing|ProcessPoolExecutor|ThreadPoolExecutor|concurrent\.futures|'
        r'joblib|\bPool\s*\(|xargs\s+[^\n]*-[^\n]*P|\bparallel\b|&[ \t]*(?:\n|$)',
        re.IGNORECASE,
    )
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {'__pycache__', '.cache', '.local'}]
        for name in files:
            path = Path(root) / name
            if path in {SIMULATE, SEQUENCES, RESULTS} or path.stat().st_size > 1_000_000:
                continue
            try:
                source = path.read_text()
            except (UnicodeDecodeError, OSError):
                continue
            if parallel_pattern.search(source):
                candidates.append((path, source))
    return candidates


def run_candidate(path, source):
    first_line = source.splitlines()[0] if source.splitlines() else ''
    if path.suffix == '.py' or 'python' in first_line.lower():
        command = [sys.executable, str(path)]
    else:
        command = ['bash', str(path)]
    return subprocess.run(
        command,
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
        check=False,
    )


def test_03_real_stiff_solver_root_finding_and_parallel_pipeline():
    import numpy
    import pandas
    import scipy
    assert numpy is not None and pandas is not None and scipy is not None

    assert SIMULATE.is_file(), '/home/user/simulate.py is missing.'
    sim_source = SIMULATE.read_text()
    assert re.search(r'scipy\.integrate|from\s+scipy\s+import\s+integrate', sim_source), (
        'simulate.py does not import scipy.integrate.'
    )
    assert 'solve_ivp' in sim_source, 'simulate.py does not use scipy.integrate.solve_ivp.'
    assert re.search(r'\b(BDF|Radau)\b', sim_source), (
        'simulate.py does not select a stiff BDF or Radau solver.'
    )

    # Exercise the requested simulation CLI on values not present in sequences.csv.
    for k_syn, d in [(0.037, 0.013), (1.73, 3.41), (6.2, 4.87)]:
        proc = subprocess.run(
            [sys.executable, str(SIMULATE), str(k_syn), str(d)],
            cwd=str(HOME),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        assert proc.returncode == 0, f'simulate.py failed: {proc.stderr}'
        try:
            actual = float(proc.stdout.strip())
        except ValueError:
            pytest.fail(f'simulate.py did not print a numeric final concentration: {proc.stdout!r}')
        expected = final_m(k_syn, d)
        assert np.isfinite(actual)
        assert abs(actual - expected) <= max(2e-6, abs(expected) * 2e-6), (
            f'simulate.py returned {actual}, expected {expected} for k_syn={k_syn}, d={d}'
        )

    candidates = pipeline_candidates()
    assert candidates, 'No master script containing a parallel batch implementation was found.'
    combined_source = sim_source + '\n' + '\n'.join(source for _, source in candidates)
    assert re.search(r'scipy\.optimize|from\s+scipy\s+import\s+optimize', combined_source), (
        'The implementation does not import scipy.optimize.'
    )
    assert re.search(r'\b(brentq|root_scalar|bisect|ridder|newton|root)\b', combined_source), (
        'No SciPy non-linear root-finding routine was found.'
    )

    original_sequences = SEQUENCES.read_bytes()
    original_results = RESULTS.read_bytes() if RESULTS.exists() else None
    requested = [
        ('probe_a', 0.031, 0.014),
        ('probe_b', 0.083, 0.041),
        ('probe_c', 0.37, 0.23),
        ('probe_d', 1.27, 0.81),
        ('probe_e', 2.91, 1.73),
        ('probe_f', 4.63, 3.29),
        ('probe_g', 7.10, 4.72),
    ]
    generated = []
    for seq_id, k_syn, chosen_d in requested:
        generated.append((seq_id, k_syn, final_m(k_syn, chosen_d)))

    successes = []
    errors = []
    try:
        for path, source in candidates:
            with open(SEQUENCES, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['SeqID', 'k_syn', 'Target_M'])
                for row in generated:
                    writer.writerow([row[0], f'{row[1]:.12g}', f'{row[2]:.12g}'])
            if RESULTS.exists():
                RESULTS.unlink()

            proc = run_candidate(path, source)
            if proc.returncode != 0 or not RESULTS.is_file():
                errors.append(f'{path}: exit={proc.returncode}, stderr={proc.stderr[-500:]}')
                continue
            try:
                actual = read_results(RESULTS)
                assert set(actual) == {row[0] for row in generated}
                expected = {}
                for seq_id, k_syn, target in generated:
                    expected[seq_id] = brentq(
                        lambda d: final_m(k_syn, d) - target,
                        0.01,
                        5.0,
                        xtol=1e-11,
                    )
                for seq_id, expected_d in expected.items():
                    assert np.isfinite(actual[seq_id])
                    assert abs(actual[seq_id] - expected_d) < 8e-4, (
                        f'{seq_id}: expected {expected_d}, got {actual[seq_id]}'
                    )
                successes.append(str(path))
                break
            except Exception as exc:
                errors.append(f'{path}: {exc}')
        assert successes, 'No parallel master script correctly processed derived probe inputs. ' + ' | '.join(errors)
    finally:
        SEQUENCES.write_bytes(original_sequences)
        if original_results is None:
            if RESULTS.exists():
                RESULTS.unlink()
        else:
            RESULTS.write_bytes(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
