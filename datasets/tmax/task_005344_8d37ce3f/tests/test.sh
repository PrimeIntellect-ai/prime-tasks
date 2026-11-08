#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
from pathlib import Path
import subprocess
import pytest

PROJECT = Path('/home/user/spectral_mcmc')
MANIFEST = PROJECT / 'Cargo.toml'
RESULTS_PATH = Path('/home/user/results.json')
DATA_PATH = Path('/home/user/spectrum.csv')


def load_results():
    assert RESULTS_PATH.exists(), f"Expected results file {RESULTS_PATH} does not exist."
    assert RESULTS_PATH.is_file(), f"Expected {RESULTS_PATH} to be a file."
    try:
        with RESULTS_PATH.open('r') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {RESULTS_PATH} as JSON: {e}")

    assert "A_mean" in data, "Key 'A_mean' is missing from results.json"
    assert "mu_mean" in data, "Key 'mu_mean' is missing from results.json"
    assert "sse" in data, "Key 'sse' is missing from results.json"

    for key in ('A_mean', 'mu_mean', 'sse'):
        assert isinstance(data[key], (int, float)), f"{key} must be a number, got {type(data[key])}"
        assert not isinstance(data[key], bool), f"{key} must be a number, not a boolean"
        assert math.isfinite(data[key]), f"{key} must be finite"
    return data


def write_dataset(a_true, mu_true, phase):
    rows = []
    with DATA_PATH.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['wavelength', 'intensity'])
        for i in range(101):
            x = -5.0 + i * 0.1
            # Deterministic, non-Gaussian-looking perturbations prevent a fixed
            # perfect-Gaussian answer while remaining below the stated noise scale.
            noise = 0.22 * math.sin(1.73 * i + phase) + 0.09 * math.cos(0.41 * i - phase)
            y = a_true * math.exp(-((x - mu_true) ** 2) / 2.0) + noise
            x = round(x, 2)
            y = round(y, 4)
            writer.writerow([x, y])
            rows.append((x, y))
    return rows


def run_program():
    if RESULTS_PATH.exists():
        RESULTS_PATH.unlink()
    proc = subprocess.run(
        ['cargo', 'run', '--release', '--quiet', '--manifest-path', str(MANIFEST)],
        cwd=str(PROJECT), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=240
    )
    assert proc.returncode == 0, f"Rust program failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    return load_results()


def calculated_sse(rows, a_mean, mu_mean):
    return sum((y - a_mean * math.exp(-((x - mu_mean) ** 2) / 2.0)) ** 2 for x, y in rows)


def assert_sse_derived(data, rows):
    expected = calculated_sse(rows, data['A_mean'], data['mu_mean'])
    tolerance = max(0.15, 0.002 * expected)
    assert abs(data['sse'] - expected) <= tolerance, \
        f"Reported SSE {data['sse']} does not match dataset-derived SSE {expected}"


def test_rust_project_and_results():
    assert PROJECT.is_dir(), f"Expected Rust project directory {PROJECT}"
    assert MANIFEST.is_file(), f"Expected Cargo manifest {MANIFEST}"
    assert 'spectral_mcmc' in MANIFEST.read_text(errors='replace'), \
        "Cargo package is not named spectral_mcmc"

    rust_files = list((PROJECT / 'src').rglob('*.rs')) if (PROJECT / 'src').is_dir() else []
    assert rust_files, "Rust project contains no source files under src/"
    source = '\n'.join(p.read_text(errors='replace') for p in rust_files).lower()
    compact = source.replace('_', '').replace(' ', '')
    assert 'spectrum.csv' in source, "Rust source does not read the required spectrum.csv dataset"
    assert '50000' in compact, "Rust source does not specify the required 50,000 iterations"
    assert '10000' in compact, "Rust source does not specify the required 10,000 burn-in"
    assert ('for' in source or 'while' in source) and 'exp' in source, \
        "Rust source does not contain the required iterative Gaussian/MCMC calculation"
    assert any(token in source for token in ('rand', 'random', 'sample', 'gen')), \
        "Rust source does not appear to perform randomized MCMC proposals"

    original_csv = DATA_PATH.read_bytes()
    hidden_outputs = []
    original_data = None
    try:
        for a_true, mu_true, phase in ((2.6, -1.7, 0.3), (6.8, 2.2, 1.1)):
            rows = write_dataset(a_true, mu_true, phase)
            data = run_program()
            assert abs(data['A_mean'] - a_true) <= 0.35, \
                f"A_mean did not track hidden dataset: expected near {a_true}, got {data['A_mean']}"
            assert abs(data['mu_mean'] - mu_true) <= 0.18, \
                f"mu_mean did not track hidden dataset: expected near {mu_true}, got {data['mu_mean']}"
            assert_sse_derived(data, rows)
            hidden_outputs.append((data['A_mean'], data['mu_mean']))
    finally:
        DATA_PATH.write_bytes(original_csv)
        original_data = run_program()

    assert abs(hidden_outputs[0][0] - hidden_outputs[1][0]) > 2.0
    assert abs(hidden_outputs[0][1] - hidden_outputs[1][1]) > 2.0

    # Preserve the original verifier's assertions on the required final run.
    A_mean = original_data['A_mean']
    mu_mean = original_data['mu_mean']
    sse = original_data['sse']
    assert 4.0 <= A_mean <= 4.4, f"A_mean out of expected bounds [4.0, 4.4]: got {A_mean}"
    assert 1.2 <= mu_mean <= 1.4, f"mu_mean out of expected bounds [1.2, 1.4]: got {mu_mean}"
    assert 15.0 <= sse <= 40.0, f"sse out of expected bounds [15.0, 40.0]: got {sse}"

    with DATA_PATH.open(newline='') as f:
        reader = csv.DictReader(f)
        original_rows = [(float(r['wavelength']), float(r['intensity'])) for r in reader]
    assert_sse_derived(original_data, original_rows)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
