#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
from pathlib import Path
import subprocess
import pytest

PROJECT_DIR = Path('/home/user/mcmc_mutations')
MANIFEST = PROJECT_DIR / 'Cargo.toml'
MAIN_RS = PROJECT_DIR / 'src' / 'main.rs'
COUNTS_FILE = Path('/home/user/data/counts.txt')
RESULTS_FILE = Path('/home/user/results.json')


def load_results():
    assert RESULTS_FILE.is_file(), f"The file {RESULTS_FILE} was not found."
    try:
        with RESULTS_FILE.open('r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {RESULTS_FILE} does not contain valid JSON.")


def run_binary(binary, counts):
    COUNTS_FILE.write_text(''.join(f'{x}\n' for x in counts))
    if RESULTS_FILE.exists():
        RESULTS_FILE.unlink()

    completed = subprocess.run(
        [str(binary)],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert completed.returncode == 0, (
        f"The compiled Rust program exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    return load_results()


def assert_dynamic_result(data, counts):
    expected_keys = {'posterior_mean', 'acceptance_rate', 'hypermutated'}
    assert set(data.keys()) == expected_keys, (
        f"results.json must contain exactly these keys: {expected_keys}"
    )

    post_mean = data['posterior_mean']
    acc_rate = data['acceptance_rate']
    hypermutated = data['hypermutated']
    assert isinstance(post_mean, (int, float)) and not isinstance(post_mean, bool)
    assert isinstance(acc_rate, (int, float)) and not isinstance(acc_rate, bool)
    assert isinstance(hypermutated, bool)
    assert math.isfinite(post_mean)
    assert math.isfinite(acc_rate)
    assert 0.0 < acc_rate <= 1.0

    # Gamma-Poisson posterior: Gamma(alpha + sum(x), beta + n).
    expected_mean = (2.0 + sum(counts)) / (1.0 + len(counts))
    tolerance = max(0.12, 0.04 * expected_mean)
    assert abs(post_mean - expected_mean) <= tolerance, (
        f"posterior_mean {post_mean} is not consistent with the input data; "
        f"expected approximately {expected_mean}"
    )
    assert hypermutated is (post_mean > 2.5)


def test_rust_project_executes_and_results_are_valid():
    assert PROJECT_DIR.is_dir(), f"Rust project directory {PROJECT_DIR} was not found."
    assert MANIFEST.is_file(), f"Cargo manifest {MANIFEST} was not found."
    assert MAIN_RS.is_file(), f"Rust binary source {MAIN_RS} was not found."
    assert MAIN_RS.stat().st_size > 0, 'src/main.rs is empty.'

    build = subprocess.run(
        ['cargo', 'build', '--release', '--manifest-path', str(MANIFEST)],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, (
        f"The Rust project did not build successfully.\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    metadata_run = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1',
         '--manifest-path', str(MANIFEST)],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert metadata_run.returncode == 0, metadata_run.stderr
    metadata = json.loads(metadata_run.stdout)
    manifest_resolved = MANIFEST.resolve()
    package = next(
        (p for p in metadata['packages']
         if Path(p['manifest_path']).resolve() == manifest_resolved),
        None,
    )
    assert package is not None, 'Cargo metadata did not contain the submitted package.'
    bin_targets = [t for t in package['targets'] if 'bin' in t.get('kind', [])]
    assert bin_targets, 'The submitted Cargo project has no binary target.'
    binary = Path(metadata['target_directory']) / 'release' / bin_targets[0]['name']
    assert binary.is_file(), f"Compiled Rust binary {binary} was not found."
    assert os.access(binary, os.X_OK), f"Compiled Rust artifact {binary} is not executable."

    original_counts = COUNTS_FILE.read_text()
    try:
        # Exercise the compiled artifact on data with analytically derived posterior means.
        low = run_binary(binary, [0] * 10)
        assert_dynamic_result(low, [0] * 10)
        high = run_binary(binary, [8] * 10)
        assert_dynamic_result(high, [8] * 10)

        # Restore the specified task input and require the submitted program to generate
        # the final results file from it.
        original_values = [int(x) for x in original_counts.splitlines() if x.strip()]
        data = run_binary(binary, original_values)
    finally:
        COUNTS_FILE.write_text(original_counts)

    # Original verifier assertions.
    assert RESULTS_FILE.is_file(), f"The file {RESULTS_FILE} was not found."
    expected_keys = {'posterior_mean', 'acceptance_rate', 'hypermutated'}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in results.json: {missing_keys}"

    post_mean = data['posterior_mean']
    acc_rate = data['acceptance_rate']
    hypermutated = data['hypermutated']

    assert isinstance(post_mean, (int, float)), 'posterior_mean must be a number.'
    assert isinstance(acc_rate, (int, float)), 'acceptance_rate must be a number.'
    assert isinstance(hypermutated, bool), 'hypermutated must be a boolean.'
    assert 2.8 <= post_mean <= 3.2, (
        f"posterior_mean {post_mean} is out of expected bounds (2.8 - 3.2)."
    )
    assert 0.1 <= acc_rate <= 0.9, (
        f"acceptance_rate {acc_rate} is out of expected bounds (0.1 - 0.9)."
    )
    assert hypermutated is True, (
        'hypermutated should be true since the posterior mean is > 2.5.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
