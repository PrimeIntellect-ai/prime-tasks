#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/markov_ci')
TRANSITIONS = Path('/home/user/transitions.csv')
RESULT = Path('/home/user/result.txt')


def run_program():
    if RESULT.exists():
        RESULT.unlink()
    subprocess.run(
        ['cargo', 'run', '--release', '--quiet'],
        cwd=PROJECT,
        check=True,
        timeout=600,
    )
    assert RESULT.is_file(), 'The Rust program did not create /home/user/result.txt.'


def parse_result():
    content = RESULT.read_text().strip()
    pattern = r'^CI for A:\s*\[(0\.\d{4}),\s*(0\.\d{4})\]$'
    match = re.match(pattern, content)
    assert match is not None, (
        f"File content '{content}' does not match expected format "
        "'CI for A: [0.xxxx, 0.yyyy]'."
    )
    return float(match.group(1)), float(match.group(2))


@pytest.fixture(scope='session', autouse=True)
def compile_and_run_submission():
    assert PROJECT.is_dir(), f'Rust project directory {PROJECT} is missing.'
    subprocess.run(
        ['cargo', 'build', '--release', '--quiet'],
        cwd=PROJECT,
        check=True,
        timeout=600,
    )
    run_program()


def test_result_file():
    result_path = '/home/user/result.txt'
    assert os.path.isfile(result_path), f'File {result_path} is missing.'

    lower_bound, upper_bound = parse_result()

    expected_lower = 0.2311
    expected_upper = 0.2546
    tolerance = 0.005

    assert abs(lower_bound - expected_lower) <= tolerance, \
        f'Lower bound {lower_bound} is not within {tolerance} of expected {expected_lower}.'
    assert abs(upper_bound - expected_upper) <= tolerance, \
        f'Upper bound {upper_bound} is not within {tolerance} of expected {expected_upper}.'


def test_rust_project_exists():
    cargo_toml = '/home/user/markov_ci/Cargo.toml'
    assert os.path.isfile(cargo_toml), f'Rust project file {cargo_toml} is missing.'

    with open(cargo_toml, 'r') as f:
        content = f.read()

    assert 'rayon' in content, "Dependency 'rayon' missing in Cargo.toml"
    assert 'rand' in content, "Dependency 'rand' missing in Cargo.toml"
    assert 'nalgebra' in content, "Dependency 'nalgebra' missing in Cargo.toml"
    assert re.search(r'(?m)^\s*rand\s*=.*0\.8', content), \
        "Dependency 'rand' must use version 0.8"

    rust_files = list(PROJECT.rglob('*.rs'))
    assert rust_files, 'The Rust project contains no Rust source files.'
    source = '\n'.join(path.read_text(errors='replace') for path in rust_files)

    assert re.search(r'\b(?:into_)?par_iter(?:_mut)?\s*\(', source), \
        'The implementation does not use a rayon parallel iterator.'
    assert 'StdRng' in source and 'seed_from_u64' in source, \
        'The implementation does not use seeded StdRng instances.'
    assert re.search(r'seed_from_u64\s*\([^)]*as\s+u64', source, re.S), \
        'The bootstrap iteration index is not used as the u64 RNG seed.'
    assert re.search(r'\.choose\s*\(', source), \
        'Bootstrap sampling does not use SliceRandom::choose.'
    assert re.search(r'\b(?:1000|1_000)\b', source), \
        'The implementation does not specify 1000 bootstrap iterations.'
    assert 'nalgebra' in source, 'The Rust source does not use nalgebra.'
    assert re.search(r'\b(?:solve|try_inverse|lu|qr|svd)\s*\(', source), \
        'No nalgebra linear-system solution operation was found.'


def test_executable_responds_to_derived_transition_models():
    original = TRANSITIONS.read_bytes()
    states = ['A', 'C', 'G', 'T']
    rng = random.SystemRandom()

    try:
        cycle_lengths = [2, 3, 4]
        rng.shuffle(cycle_lengths)

        for cycle_length in cycle_lengths:
            others = states[1:]
            rng.shuffle(others)
            cycle = ['A'] + others[:cycle_length - 1]
            rng.shuffle(cycle)

            successors = {}
            for index, state in enumerate(cycle):
                successors[state] = cycle[(index + 1) % len(cycle)]
            for state in states:
                if state not in successors:
                    successors[state] = 'A'

            lines = []
            for state in states:
                lines.extend(f'{state},{successors[state]}' for _ in range(500))
            rng.shuffle(lines)
            TRANSITIONS.write_text('\n'.join(lines) + '\n')

            run_program()
            lower, upper = parse_result()
            expected = round(1.0 / cycle_length, 4)
            assert abs(lower - expected) <= 0.0001, \
                f'Derived lower bound {lower} should be {expected} for a {cycle_length}-state cycle.'
            assert abs(upper - expected) <= 0.0001, \
                f'Derived upper bound {upper} should be {expected} for a {cycle_length}-state cycle.'
    finally:
        TRANSITIONS.write_bytes(original)
        run_program()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
