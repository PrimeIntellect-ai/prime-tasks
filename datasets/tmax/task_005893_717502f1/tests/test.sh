#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/tx_analyzer')
MANIFEST = PROJECT / 'Cargo.toml'
INPUT = Path('/home/user/tx_data.json')
OUTPUT = Path('/home/user/resolution.txt')

ORIGINAL_EXPECTED = """Deadlock: TX_003, TX_005
Safe_TX_003_Step1: MATCH (n:User {uid: 512}) SET n.status = 'updated'
Safe_TX_003_Step2: MATCH (n:User {uid: 882}) SET n.status = 'updated'
Safe_TX_005_Step1: MATCH (n:User {uid: 512}) SET n.status = 'updated'
Safe_TX_005_Step2: MATCH (n:User {uid: 882}) SET n.status = 'updated'"""


def normalized_lines(content):
    return [line.strip() for line in content.splitlines() if line.strip()]


def assert_resolution(expected):
    assert OUTPUT.exists(), f'The file {OUTPUT} is missing. Did the Rust analyzer generate the output log?'
    assert OUTPUT.is_file(), f'The path {OUTPUT} is not a file.'

    actual_lines = normalized_lines(OUTPUT.read_text())
    expected_lines = normalized_lines(expected)
    assert len(actual_lines) == len(expected_lines), (
        f'Expected {len(expected_lines)} lines in {OUTPUT}, but found {len(actual_lines)}.'
    )
    for i, (actual, wanted) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == wanted, (
            f'Line {i + 1} in {OUTPUT} does not match.\n'
            f'Expected: {wanted}\nActual:   {actual}'
        )


def cargo(args, timeout=180):
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', 'env', 'HOME=/home/user', 'cargo', *args],
        cwd=str(PROJECT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Cargo command failed:\n{result.stdout}"
    return result.stdout


def run_analyzer(expected):
    if OUTPUT.exists():
        OUTPUT.unlink()
    cargo(['run', '--quiet', '--manifest-path', str(MANIFEST)])
    assert_resolution(expected)


def make_random_case():
    rng = secrets.SystemRandom()
    tx_numbers = rng.sample(range(100000, 999999), 5)
    tx_ids = [f'TX_{number}' for number in tx_numbers]
    uids = rng.sample(range(10000, 999999), 8)

    dead_a, dead_b = tx_ids[0], tx_ids[1]
    lower, higher = sorted(uids[:2])
    records = [
        {
            'tx_id': dead_a,
            'queries': [
                f"MATCH (n:User {{uid: {higher}}}) SET n.status = 'updated'",
                f"MATCH (n:User {{uid: {lower}}}) SET n.status = 'updated'",
            ],
        },
        {
            'tx_id': dead_b,
            'queries': [
                f"MATCH (n:User {{uid: {lower}}}) SET n.status = 'updated'",
                f"MATCH (n:User {{uid: {higher}}}) SET n.status = 'updated'",
            ],
        },
    ]

    for index, tx_id in enumerate(tx_ids[2:]):
        first = uids[2 + index * 2]
        second = uids[3 + index * 2]
        records.append({
            'tx_id': tx_id,
            'queries': [
                f"MATCH (n:User {{uid: {first}}}) SET n.status = 'updated'",
                f"MATCH (n:User {{uid: {second}}}) SET n.status = 'updated'",
            ],
        })

    rng.shuffle(records)
    sorted_a, sorted_b = sorted([dead_a, dead_b])
    expected = f"""Deadlock: {sorted_a}, {sorted_b}
Safe_{sorted_a}_Step1: MATCH (n:User {{uid: {lower}}}) SET n.status = 'updated'
Safe_{sorted_a}_Step2: MATCH (n:User {{uid: {higher}}}) SET n.status = 'updated'
Safe_{sorted_b}_Step1: MATCH (n:User {{uid: {lower}}}) SET n.status = 'updated'
Safe_{sorted_b}_Step2: MATCH (n:User {{uid: {higher}}}) SET n.status = 'updated'"""
    return records, expected


def test_tx_analyzer_project_exists_and_is_rust_binary():
    assert PROJECT.exists(), f'The directory {PROJECT} is missing. Did you initialize the Rust project?'
    assert PROJECT.is_dir(), f'The path {PROJECT} is not a directory.'
    assert MANIFEST.exists(), f'Cargo.toml is missing in {PROJECT}. Is it a valid Rust project?'

    metadata_text = cargo(['metadata', '--no-deps', '--format-version', '1'])
    metadata = json.loads(metadata_text)
    root_manifest = MANIFEST.resolve()
    packages = [p for p in metadata['packages'] if Path(p['manifest_path']).resolve() == root_manifest]
    assert packages, 'Cargo.toml does not define a Rust package at /home/user/tx_analyzer.'
    binary_targets = [t for t in packages[0]['targets'] if 'bin' in t.get('kind', [])]
    assert binary_targets, 'The Rust package does not define an executable binary target.'
    for target in binary_targets:
        source = Path(target['src_path']).resolve()
        assert source.suffix == '.rs', f'Binary target source is not a Rust source file: {source}'
        assert source.is_file(), f'Rust binary source is missing: {source}'
        assert PROJECT.resolve() in source.parents, 'Rust binary source must be inside the tx_analyzer project.'


def test_analyzer_execution_and_resolution_content():
    original_input = INPUT.read_bytes()
    try:
        # Preserve the original exact-content assertion, but require the submitted
        # Rust executable to regenerate the file first.
        run_analyzer(ORIGINAL_EXPECTED)

        # Exercise the analyzer on unpredictable valid inputs so a fixed answer
        # cannot pass without parsing tx_data.json.
        for _ in range(3):
            records, expected = make_random_case()
            INPUT.write_text(json.dumps(records, indent=2) + '\n')
            run_analyzer(expected)

        # Restore the supplied data and verify the original result once more.
        INPUT.write_bytes(original_input)
        run_analyzer(ORIGINAL_EXPECTED)
    finally:
        INPUT.write_bytes(original_input)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
