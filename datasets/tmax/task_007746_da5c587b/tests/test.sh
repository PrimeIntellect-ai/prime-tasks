#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import subprocess

import pytest

LOG_PATH = Path('/home/user/jwt_logs.txt')
OUTPUT_PATH = Path('/home/user/rotated_tokens.json')
SECRET = 'SuperSecretKey2023'


def decode_b64url(s):
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))


def encode_b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')


def jwt_part(value):
    return encode_b64url(json.dumps(value, separators=(',', ':')).encode('utf-8'))


def unsigned_token(header, payload):
    return f'{jwt_part(header)}.{jwt_part(payload)}.'


def expected_users_from_log(path):
    users = set()
    for raw_line in path.read_text().splitlines():
        token = raw_line.strip()
        if not token:
            continue
        parts = token.split('.')
        assert len(parts) == 3, f'Log entry is not a three-part JWT: {token}'
        header = json.loads(decode_b64url(parts[0]))
        if header.get('alg') == 'none':
            payload = json.loads(decode_b64url(parts[1]))
            assert isinstance(payload.get('sub'), str), 'Vulnerable token has no string sub field.'
            users.add(payload['sub'])
    return users


def find_rust_command():
    preferred = Path('/home/user/jwt_rotator/Cargo.toml')
    manifests = []
    if preferred.is_file():
        manifests.append(preferred)

    for manifest in sorted(Path('/home/user').rglob('Cargo.toml')):
        if manifest == preferred or 'target' in manifest.parts or '.cargo' in manifest.parts:
            continue
        manifests.append(manifest)

    for manifest in manifests:
        project = manifest.parent
        rust_sources = [p for p in project.rglob('*.rs') if 'target' not in p.parts]
        if rust_sources:
            return ['cargo', 'run', '--quiet', '--manifest-path', str(manifest)], project

    sources = [
        p for p in sorted(Path('/home/user').rglob('*.rs'))
        if 'target' not in p.parts and '.cargo' not in p.parts
    ]
    assert sources, 'No Rust source file or Cargo project was found under /home/user.'

    source = next((p for p in sources if p.name == 'main.rs'), sources[0])
    binary = Path('/tmp/submitted_jwt_rotator')
    compile_result = subprocess.run(
        ['rustc', str(source), '-o', str(binary)],
        cwd=str(source.parent),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=240,
    )
    assert compile_result.returncode == 0, f'Rust source did not compile:\n{compile_result.stdout}'
    return [str(binary)], source.parent


def run_rotator(command, cwd):
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    result = subprocess.run(
        command,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=240,
    )
    assert result.returncode == 0, f'Rust program failed:\n{result.stdout}'
    assert OUTPUT_PATH.is_file(), 'The file /home/user/rotated_tokens.json is missing.'


def verify_and_decode_jwt(token, secret):
    assert isinstance(token, str), 'JWT value must be a string.'
    parts = token.split('.')
    assert len(parts) == 3, f'JWT must have 3 parts, got {len(parts)}'

    header_b64, payload_b64, signature_b64 = parts
    msg = f'{header_b64}.{payload_b64}'.encode('utf-8')
    expected_sig = hmac.new(secret.encode('utf-8'), msg, hashlib.sha256).digest()
    expected_sig_b64 = base64.urlsafe_b64encode(expected_sig).rstrip(b'=').decode('utf-8')
    assert signature_b64 == expected_sig_b64, 'JWT signature is invalid.'

    header = json.loads(decode_b64url(header_b64))
    payload = json.loads(decode_b64url(payload_b64))
    return header, payload


def validate_output(expected_users):
    assert OUTPUT_PATH.is_file(), 'The file /home/user/rotated_tokens.json is missing.'
    try:
        with OUTPUT_PATH.open('r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail('/home/user/rotated_tokens.json is not valid JSON.')

    assert isinstance(data, dict), '/home/user/rotated_tokens.json must contain a JSON object.'
    actual_users = set(data.keys())
    assert actual_users == expected_users, f'Expected users {expected_users}, but got {actual_users}.'

    for user in expected_users:
        header, payload = verify_and_decode_jwt(data[user], SECRET)
        assert header.get('alg') == 'HS256', f"Expected alg 'HS256' for user {user}, got {header.get('alg')}"
        assert header.get('typ') == 'JWT', f"Expected typ 'JWT' for user {user}, got {header.get('typ')}"
        assert payload.get('sub') == user, f"Expected sub '{user}' for user {user}, got {payload.get('sub')}"
        assert payload.get('iat') == 1700000000, f"Expected iat 1700000000 for user {user}, got {payload.get('iat')}"
        assert isinstance(payload.get('iat'), int), f'Expected iat to be an integer for user {user}.'


def test_rust_program_parses_logs_and_rotates_tokens():
    assert LOG_PATH.is_file(), 'The file /home/user/jwt_logs.txt is missing.'
    original_log = LOG_PATH.read_bytes()
    command, cwd = find_rust_command()
    saved_output = None

    try:
        # Execute the submitted Rust implementation against the supplied log.
        run_rotator(command, cwd)
        validate_output(expected_users_from_log(LOG_PATH))
        saved_output = OUTPUT_PATH.read_bytes()

        # Replace the log with unpredictable users so a hardcoded final JSON cannot pass.
        for _ in range(2):
            vulnerable_a = 'affected_' + secrets.token_hex(8)
            vulnerable_b = 'affected_' + secrets.token_hex(8)
            safe_user = 'safe_' + secrets.token_hex(8)
            lines = [
                unsigned_token({'alg': 'HS256', 'typ': 'JWT'}, {'sub': safe_user, 'iat': 1699999999})[:-1] + 'dummy_signature',
                unsigned_token({'alg': 'none'}, {'sub': vulnerable_a}),
                unsigned_token({'typ': 'JWT', 'alg': 'none'}, {'sub': vulnerable_b, 'extra': True}),
            ]
            LOG_PATH.write_text('\n'.join(lines) + '\n')
            expected = expected_users_from_log(LOG_PATH)
            run_rotator(command, cwd)
            validate_output(expected)
    finally:
        LOG_PATH.write_bytes(original_log)
        if saved_output is not None:
            OUTPUT_PATH.write_bytes(saved_output)
        elif OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
