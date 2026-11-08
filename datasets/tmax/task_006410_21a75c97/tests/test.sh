#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import json
import os
from pathlib import Path
import subprocess

PROJECT = Path('/home/user/credential_rotator')
OUTPUT = Path('/home/user/rotated_credentials.csv')
LEGACY_DB = Path('/home/user/legacy_db.csv')
WORDLIST = Path('/home/user/wordlist.txt')
MASTER_KEY = Path('/home/user/master.key')


def run_rust_application():
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        'The Rust credential_rotator application failed to run.\n'
        f'stdout:\n{result.stdout}\n'
        f'stderr:\n{result.stderr}'
    )


def derive_expected_lines():
    assert MASTER_KEY.exists(), f'Master key file {MASTER_KEY} is missing.'
    with MASTER_KEY.open('rb') as f:
        master_key = f.read()

    assert WORDLIST.exists(), f'Wordlist file {WORDLIST} is missing.'
    with WORDLIST.open('r') as f:
        words = f.read().splitlines()

    hash_to_plaintext = {}
    for word in words:
        sha256_hash = hashlib.sha256(word.encode('utf-8')).hexdigest()
        hash_to_plaintext[sha256_hash] = word

    assert LEGACY_DB.exists(), f'Legacy DB file {LEGACY_DB} is missing.'
    expected_lines = []
    with LEGACY_DB.open('r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            if len(parts) != 2:
                continue
            username, pw_hash = parts
            if pw_hash in hash_to_plaintext:
                cracked_password = hash_to_plaintext[pw_hash]
                token = hmac.new(
                    master_key, username.encode('utf-8'), hashlib.sha256
                ).hexdigest()
                expected_lines.append(f'{username},{cracked_password},{token}')

    expected_lines.sort()
    return expected_lines


def assert_output_matches_inputs():
    assert OUTPUT.exists(), (
        f'Expected output file {OUTPUT} is missing. '
        'Did the Rust program run and create it?'
    )
    assert OUTPUT.is_file(), f'Path {OUTPUT} exists but is not a regular file.'

    expected_lines = derive_expected_lines()
    with OUTPUT.open('r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f'Output file {OUTPUT} contains {len(actual_lines)} lines, '
        f'but expected {len(expected_lines)} lines based on successfully cracked users.'
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f'Line {i + 1} in {OUTPUT} is incorrect.\n'
            f"Expected: '{expected}'\n"
            f"Actual:   '{actual}'\n"
            "Ensure the format is 'username,cracked_password,new_token', the token "
            'is a lowercase hex HMAC-SHA256 digest, and lines are sorted alphabetically by username.'
        )


def test_rust_application_generates_credentials_correctly():
    assert PROJECT.exists(), f'Expected Cargo project {PROJECT} is missing.'
    assert PROJECT.is_dir(), f'{PROJECT} is not a directory.'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing from credential_rotator.'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'src/main.rs is missing from credential_rotator.'

    metadata_result = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1',
         '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, (
        'credential_rotator is not a valid Cargo project.\n'
        f'{metadata_result.stderr}'
    )
    metadata = json.loads(metadata_result.stdout)
    assert any(
        'bin' in target.get('kind', [])
        for package in metadata.get('packages', [])
        for target in package.get('targets', [])
    ), 'The Cargo project does not define a Rust binary application.'

    # Remove any pre-generated answer and require the Cargo application to recreate it.
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    run_rust_application()

    # Preserve all of the original verifier's exact behavioral assertions.
    assert_output_matches_inputs()

    original_db = LEGACY_DB.read_bytes()
    original_wordlist = WORDLIST.read_bytes()
    original_key = MASTER_KEY.read_bytes()
    original_output = OUTPUT.read_bytes()

    try:
        challenge_words = ['deltaPass', 'alphaPass', 'zuluPass', 'unusedPass']
        challenge_records = [
            ('zulu', 'zuluPass'),
            ('alpha', 'alphaPass'),
            ('missing', None),
            ('delta', 'deltaPass'),
        ]
        WORDLIST.write_text('\n'.join(challenge_words) + '\n')
        MASTER_KEY.write_bytes(b'verifier-dynamic-secret-key')

        db_lines = []
        for username, password in challenge_records:
            if password is None:
                pw_hash = hashlib.sha256(b'not-in-the-wordlist').hexdigest()
            else:
                pw_hash = hashlib.sha256(password.encode('utf-8')).hexdigest()
            db_lines.append(f'{username},{pw_hash}')
        LEGACY_DB.write_text('\n'.join(db_lines) + '\n')

        OUTPUT.unlink()
        run_rust_application()
        assert_output_matches_inputs()
    finally:
        LEGACY_DB.write_bytes(original_db)
        WORDLIST.write_bytes(original_wordlist)
        MASTER_KEY.write_bytes(original_key)
        OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
