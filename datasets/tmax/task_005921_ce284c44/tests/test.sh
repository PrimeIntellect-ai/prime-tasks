#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import pytest

PROJECT = '/home/user/mcmc_solver'
OUTPUT = '/home/user/posterior_mean.txt'
OBS = '/home/user/y_obs.csv'


def solver_command():
    if os.path.isdir(PROJECT):
        cargo_toml = os.path.join(PROJECT, 'Cargo.toml')
        assert os.path.isfile(cargo_toml), f'Missing Cargo project file: {cargo_toml}'
        rust_sources = []
        for root, _, files in os.walk(PROJECT):
            rust_sources.extend(os.path.join(root, f) for f in files if f.endswith('.rs'))
        assert rust_sources, 'The mcmc_solver project contains no Rust source files.'
        subprocess.run(
            ['cargo', 'clean', '--quiet'], cwd=PROJECT, check=True, timeout=60,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        return ['cargo', 'run', '--release', '--quiet'], PROJECT

    assert os.path.isfile(PROJECT), f'Rust program {PROJECT} was not found.'
    assert os.access(PROJECT, os.X_OK), f'{PROJECT} is not executable.'
    with open(PROJECT, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{PROJECT} is not a compiled executable.'
    source = PROJECT + '.rs'
    assert os.path.isfile(source), f'Missing Rust source file: {source}'
    return [PROJECT], '/home/user'


def root_for_x(x):
    y = x
    for _ in range(100):
        nxt = y - (y*y*y + y - x) / (3*y*y + 1)
        if abs(nxt - y) < 1e-12:
            return nxt
        y = nxt
    return y


def synthetic_observations(mu):
    rng = random.Random(73129)
    z = []
    for _ in range(50):
        v = rng.gauss(0.0, 1.0)
        z.extend((v, -v))
    return [root_for_x(mu + v) for v in z]


def write_observations(values):
    with open(OBS, 'w') as f:
        for value in values:
            f.write(f'{value:.17g}\n')


def run_solver(command, cwd):
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        command, cwd=cwd, timeout=240,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, (
        f'mcmc_solver failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.exists(OUTPUT), f'Error: output file {OUTPUT} not found after running the solver.'
    assert os.path.isfile(OUTPUT), f'Error: {OUTPUT} is not a file.'
    with open(OUTPUT, 'r') as f:
        val_str = f.read().strip()
    assert re.fullmatch(r'[+-]?\d+\.\d{2}', val_str), (
        f"Expected exactly two decimal places, found '{val_str}'."
    )
    try:
        val = float(val_str)
    except ValueError:
        pytest.fail(f"Error: content '{val_str}' in {OUTPUT} is not a valid float.")
    assert math.isfinite(val), f'Output value {val} is not finite.'
    return val, val_str


def test_solver_and_posterior_mean_file():
    command, cwd = solver_command()
    with open(OBS, 'rb') as f:
        original_observations = f.read()

    try:
        # Exercise the Rust program on independently generated observations so a
        # constant posterior_mean.txt cannot pass.
        for expected_mu in (-1.5, 3.5):
            write_observations(synthetic_observations(expected_mu))
            val, _ = run_solver(command, cwd)
            assert abs(val - expected_mu) <= 0.8, (
                f'For synthetic observations generated at mu={expected_mu}, '
                f'the solver returned {val}.'
            )

        # Restore the task input, execute the solver on it, and retain the
        # original verifier's output assertions.
        with open(OBS, 'wb') as f:
            f.write(original_observations)
        val, val_str = run_solver(command, cwd)

        assert 1.7 <= val <= 2.3, (
            f'Error: value {val} is outside acceptable range [1.7, 2.3].'
        )
        if '.' in val_str:
            decimals = val_str.split('.')[-1]
            assert len(decimals) == 2, (
                f"Expected 2 decimal places, found {len(decimals)} in '{val_str}'."
            )
        else:
            pytest.fail(
                f"Expected value to be formatted to 2 decimal places, but no decimal point found in '{val_str}'."
            )
    finally:
        with open(OBS, 'wb') as f:
            f.write(original_observations)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
