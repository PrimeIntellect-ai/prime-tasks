#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import secrets
import subprocess

import h5py
import numpy as np

PROJECT_DIR = pathlib.Path('/home/user/fit_model')
CARGO_TOML = PROJECT_DIR / 'Cargo.toml'
RESULT_FILE = pathlib.Path('/home/user/fit_result.txt')
OBSERVATION_FILE = pathlib.Path('/home/user/observation.h5')


def test_01_fit_result_exists_and_correct():
    """Preserve the original check for the result produced from the supplied data."""
    assert RESULT_FILE.is_file(), f"Expected result file {RESULT_FILE} does not exist."

    with RESULT_FILE.open('r') as f:
        content = f.read().strip()

    expected = "2.0000,0.0600"
    assert content == expected, f"File content '{content}' does not match expected '{expected}'."


def test_02_rust_project_exists():
    """Preserve the original project and hdf5 dependency checks."""
    assert PROJECT_DIR.is_dir(), f"Rust project directory {PROJECT_DIR} does not exist."
    assert CARGO_TOML.is_file(), f"Cargo.toml not found in {PROJECT_DIR}."

    with CARGO_TOML.open('r') as f:
        content = f.read()

    assert 'hdf5' in content, "The 'hdf5' crate is not listed as a dependency in Cargo.toml."


def test_03_project_is_rust_and_executes_regression():
    rust_sources = [p for p in PROJECT_DIR.rglob('*.rs') if p.is_file()]
    assert rust_sources, "No Rust source files were found in the project."
    assert any('hdf5' in p.read_text(errors='ignore') for p in rust_sources), \
        "The Rust source does not use or reference the hdf5 crate."

    metadata_run = subprocess.run(
        ['cargo', 'metadata', '--format-version', '1', '--no-deps'],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert metadata_run.returncode == 0, f"cargo metadata failed:\n{metadata_run.stderr}"
    metadata = json.loads(metadata_run.stdout)
    dependencies = [
        dep
        for package in metadata.get('packages', [])
        for dep in package.get('dependencies', [])
    ]
    assert any(dep.get('name') == 'hdf5' for dep in dependencies), \
        "Cargo metadata does not declare the hdf5 crate as a dependency."

    original_h5 = OBSERVATION_FILE.read_bytes()
    original_result = RESULT_FILE.read_bytes()
    rng = secrets.SystemRandom()

    try:
        for size in (7, 11):
            x = np.array([rng.uniform(-12.0, 15.0) for _ in range(size)], dtype=np.float64)
            y = np.array([rng.uniform(-25.0, 30.0) for _ in range(size)], dtype=np.float64)

            x_mean = float(np.mean(x))
            y_mean = float(np.mean(y))
            slope = float(np.sum((x - x_mean) * (y - y_mean)) / np.sum((x - x_mean) ** 2))
            intercept = y_mean - slope * x_mean
            expected = f"{slope:.4f},{intercept:.4f}"

            with h5py.File(OBSERVATION_FILE, 'w') as f:
                f.create_dataset('x', data=x)
                f.create_dataset('y', data=y)

            if RESULT_FILE.exists():
                RESULT_FILE.unlink()

            run = subprocess.run(
                ['cargo', 'run', '--quiet'],
                cwd=PROJECT_DIR,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=240,
            )
            assert run.returncode == 0, \
                f"Rust program failed on generated input:\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"
            assert RESULT_FILE.is_file(), "Rust program did not create /home/user/fit_result.txt."
            actual = RESULT_FILE.read_text().strip()
            assert actual == expected, \
                f"Generated-data result '{actual}' does not match OLS result '{expected}'."
    finally:
        OBSERVATION_FILE.write_bytes(original_h5)
        RESULT_FILE.write_bytes(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
