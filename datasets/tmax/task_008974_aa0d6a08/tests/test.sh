#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
from pathlib import Path
import secrets
import subprocess

PROJECT = Path('/home/user/data_prep')
MANIFEST = PROJECT / 'Cargo.toml'
SOURCE = PROJECT / 'src/main.rs'
DATA_DIR = Path('/home/user/data')
OUTPUT = Path('/home/user/means.txt')


def assert_rust_project():
    assert PROJECT.is_dir(), f'{PROJECT} does not exist or is not a directory.'
    assert MANIFEST.is_file(), f'{MANIFEST} does not exist or is not a file.'
    assert SOURCE.is_file(), f'{SOURCE} does not exist or is not a file.'
    assert SOURCE.stat().st_size > 0, f'{SOURCE} is empty.'

    result = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1', '--manifest-path', str(MANIFEST)],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f'Invalid Rust project:\n{result.stderr}'
    metadata = json.loads(result.stdout)
    expected_source = SOURCE.resolve()
    bin_sources = [
        Path(target['src_path']).resolve()
        for package in metadata['packages']
        for target in package['targets']
        if 'bin' in target['kind']
    ]
    assert expected_source in bin_sources, 'src/main.rs is not configured as a Rust binary target.'


def write_csv(path, fieldnames, rows):
    with path.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def install_inputs(users, scores):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    write_csv(DATA_DIR / 'users.csv', ['id', 'factor'], users)
    write_csv(DATA_DIR / 'scores.csv', ['user_id', 'score'], scores)


def run_program():
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(MANIFEST)],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, f'Rust program failed to compile or run:\n{result.stderr}'


def read_and_check_output(expected_lines):
    output_file = '/home/user/means.txt'
    assert os.path.exists(output_file), f'{output_file} does not exist. Did you run the Rust program?'
    assert os.path.isfile(output_file), f'{output_file} is not a file.'

    with open(output_file, 'r') as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == len(expected_lines), f'Expected {len(expected_lines)} lines in {output_file}, but found {len(lines)}.'
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} in {output_file} is incorrect. Expected '{expected}', got '{actual.strip()}'."


def derive_expected(users, scores):
    factors = {int(row['id']): float(row['factor']) for row in users}
    joined = sorted(
        (int(row['user_id']), factors[int(row['user_id'])] * float(row['score']))
        for row in scores
        if int(row['user_id']) in factors
    )
    combined = [value for _, value in joined]
    n = len(combined)
    expected = []
    for sample_idx in range(3):
        sample = [combined[((i + 1) * (sample_idx + 2) * 17) % n] for i in range(n)]
        mean = sum(sample) / n
        if mean > 0.0:
            expected.append(f'{mean:.2f}')
    return expected


def test_rust_program_and_generated_means():
    assert_rust_project()

    canonical_users = [
        {'id': '1', 'factor': '1.5'},
        {'id': '2', 'factor': '2.0'},
        {'id': '3', 'factor': '0.8'},
        {'id': '4', 'factor': '1.2'},
        {'id': '5', 'factor': '3.0'},
    ]
    canonical_scores = [
        {'user_id': '2', 'score': '20.0'},
        {'user_id': '3', 'score': '50.0'},
        {'user_id': '4', 'score': '15.0'},
        {'user_id': '5', 'score': '10.0'},
        {'user_id': '6', 'score': '100.0'},
    ]
    install_inputs(canonical_users, canonical_scores)
    run_program()
    read_and_check_output(['29.00', '32.00', '40.00'])

    rng = secrets.SystemRandom()
    joined_ids = sorted(rng.sample(range(1000, 9000), 6))
    factors = [
        -rng.randint(10, 20),
        rng.randint(2, 15),
        rng.randint(25, 40),
        -rng.randint(10, 20),
        rng.randint(25, 40),
        rng.randint(2, 15),
    ]
    scores_values = [
        rng.randint(2, 4),
        rng.randint(2, 7),
        rng.randint(3, 5),
        rng.randint(2, 4),
        rng.randint(3, 5),
        rng.randint(2, 7),
    ]
    users = [
        {'id': str(uid), 'factor': f'{factor}.0'}
        for uid, factor in zip(joined_ids, factors)
    ]
    scores = [
        {'user_id': str(uid), 'score': f'{score}.0'}
        for uid, score in zip(joined_ids, scores_values)
    ]
    users.append({'id': str(rng.randrange(9001, 9500)), 'factor': '999.0'})
    scores.append({'user_id': str(rng.randrange(9501, 9999)), 'score': '999.0'})
    rng.shuffle(users)
    rng.shuffle(scores)

    expected = derive_expected(users, scores)
    assert len(expected) == 2, 'Internal randomized test did not exercise mean validation.'
    install_inputs(users, scores)
    run_program()
    read_and_check_output(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
