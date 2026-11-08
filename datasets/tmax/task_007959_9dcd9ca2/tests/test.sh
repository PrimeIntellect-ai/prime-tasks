#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import re
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import pytest
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad

RESULT_FILE = Path('/home/user/rotation_result.txt')
KEY_FILE = Path('/home/user/key.txt')
IV_FILE = Path('/home/user/iv.txt')
ACCESS_LOG = Path('/home/user/access.log')


def get_expected_leaked_token():
    key = KEY_FILE.read_bytes().strip()
    iv = IV_FILE.read_bytes().strip()
    for line in ACCESS_LOG.read_text().splitlines():
        match = re.search(r'"(?:GET|POST)\s+(\S+)\s+HTTP/[^\"]+"\s+(\d{3})\b', line)
        if not match or match.group(2) != '200':
            continue
        parsed = urlsplit(match.group(1))
        if parsed.path != '/api/admin':
            continue
        tokens = parse_qs(parsed.query).get('token', [])
        if len(tokens) == 1:
            ciphertext = base64.b64decode(tokens[0], validate=True)
            plaintext = unpad(AES.new(key, AES.MODE_CBC, iv).decrypt(ciphertext), AES.block_size)
            return plaintext.decode('utf-8')
    raise AssertionError('No successful /api/admin token was found in the access log.')


def read_result():
    return RESULT_FILE.read_text()


def extract_field(content, name):
    match = re.search(rf'^{re.escape(name)}:\s*(.+)$', content, re.MULTILINE)
    assert match is not None, f"Could not find '{name}: <value>' in the result file."
    return match.group(1).strip()


def assert_result_values(expected_leaked):
    content = read_result()
    leaked_token = extract_field(content, 'Leaked')
    assert leaked_token == expected_leaked, f'Incorrect leaked token. Expected {expected_leaked}, got {leaked_token}'

    expected_new_token = expected_leaked + '_rotated'
    actual_hash = extract_field(content, 'New_Hash')
    expected_hash = hashlib.sha256(expected_new_token.encode('utf-8')).hexdigest()
    assert actual_hash == expected_hash, f'Incorrect New_Hash. Expected {expected_hash}, got {actual_hash}'

    b64_encrypted = extract_field(content, 'New_Encrypted')
    key = KEY_FILE.read_bytes().strip()
    iv = IV_FILE.read_bytes().strip()
    try:
        ciphertext = base64.b64decode(b64_encrypted, validate=True)
        decrypted = unpad(AES.new(key, AES.MODE_CBC, iv).decrypt(ciphertext), AES.block_size).decode('utf-8')
    except Exception as exc:
        pytest.fail(f'Failed to decrypt New_Encrypted token: {exc}')
    assert decrypted == expected_new_token, f'Decrypted new token does not match expected. Expected {expected_new_token}, got {decrypted}'


def test_result_file_exists():
    assert RESULT_FILE.is_file(), f'The result file {RESULT_FILE} is missing.'


def test_result_format_and_leaked_token():
    content = read_result()
    leaked_token = extract_field(content, 'Leaked')
    expected = get_expected_leaked_token()
    assert leaked_token == expected, f'Incorrect leaked token. Expected {expected}, got {leaked_token}'


def test_result_new_hash():
    content = read_result()
    actual_hash = extract_field(content, 'New_Hash')
    expected_new_token = get_expected_leaked_token() + '_rotated'
    expected_hash = hashlib.sha256(expected_new_token.encode('utf-8')).hexdigest()
    assert actual_hash == expected_hash, f'Incorrect New_Hash. Expected {expected_hash}, got {actual_hash}'


def test_result_new_encrypted_token():
    content = read_result()
    b64_encrypted = extract_field(content, 'New_Encrypted')
    key = KEY_FILE.read_bytes().strip()
    iv = IV_FILE.read_bytes().strip()
    process = subprocess.Popen(
        ['openssl', 'enc', '-d', '-aes-128-cbc', '-K', key.hex(), '-iv', iv.hex(), '-base64', '-A'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    stdout, stderr = process.communicate(input=b64_encrypted.encode('utf-8'))
    assert process.returncode == 0, f'Failed to decrypt New_Encrypted token using openssl. Error: {stderr.decode()}'
    expected_new_token = get_expected_leaked_token() + '_rotated'
    decrypted_new_token = stdout.decode('utf-8')
    assert decrypted_new_token == expected_new_token, f'Decrypted new token does not match expected. Expected {expected_new_token}, got {decrypted_new_token}'


def test_cpp_program_performs_rotation():
    sources = []
    for pattern in ('*.cpp', '*.cc', '*.cxx'):
        sources.extend(Path('/home/user').rglob(pattern))
    assert sources, 'No C++ source program was written under /home/user.'

    compiled = []
    build_dir = Path(tempfile.mkdtemp(prefix='rotation-build-'))
    for index, source in enumerate(sources):
        binary = build_dir / f'candidate-{index}'
        process = subprocess.run(
            ['g++', '-std=c++17', str(source), '-o', str(binary), '-lssl', '-lcrypto'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        if process.returncode == 0:
            compiled.append(binary)
    assert compiled, 'No submitted C++ source could be compiled with OpenSSL/libcrypto.'

    original_key = KEY_FILE.read_bytes()
    original_iv = IV_FILE.read_bytes()
    original_log = ACCESS_LOG.read_bytes()
    original_result = RESULT_FILE.read_bytes() if RESULT_FILE.exists() else None

    challenge_key = b'k7P2m9Q4v6X1c8Za'
    challenge_iv = b'R5t0N3y8B2w7L9s4'
    challenge_token = 'audit_token_' + os.urandom(10).hex()

    def encrypt(value):
        cipher = AES.new(challenge_key, AES.MODE_CBC, challenge_iv)
        return base64.b64encode(cipher.encrypt(pad(value.encode('utf-8'), AES.block_size))).decode('ascii')

    challenge_log = (
        f'192.0.2.10 - - [12/Sep/2026:10:00:00 +0000] "GET /api/admin?token={encrypt("rejected_token")} HTTP/1.1" 403 120\n'
        f'198.51.100.8 - - [12/Sep/2026:10:01:00 +0000] "GET /api/admin?token={encrypt(challenge_token)} HTTP/1.1" 200 512\n'
        f'203.0.113.4 - - [12/Sep/2026:10:02:00 +0000] "GET /other?token={encrypt("irrelevant_token")} HTTP/1.1" 200 64\n'
    ).encode('utf-8')

    errors = []
    succeeded = False
    try:
        for binary in compiled:
            KEY_FILE.write_bytes(challenge_key)
            IV_FILE.write_bytes(challenge_iv)
            ACCESS_LOG.write_bytes(challenge_log)
            RESULT_FILE.unlink(missing_ok=True)
            try:
                process = subprocess.run(
                    [str(binary)],
                    cwd='/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=30,
                )
                if process.returncode != 0:
                    errors.append(f'{binary.name} exited with {process.returncode}: {process.stderr.decode(errors="replace")}')
                    continue
                if not RESULT_FILE.exists() and process.stdout:
                    RESULT_FILE.write_bytes(process.stdout)
                assert RESULT_FILE.is_file(), 'The executed C++ program did not produce rotation_result.txt or result output.'
                assert_result_values(challenge_token)
                succeeded = True
                break
            except Exception as exc:
                errors.append(f'{binary.name}: {exc}')
        assert succeeded, 'No compiled C++ program correctly processed a fresh log/key/IV challenge. ' + ' | '.join(errors)
    finally:
        KEY_FILE.write_bytes(original_key)
        IV_FILE.write_bytes(original_iv)
        ACCESS_LOG.write_bytes(original_log)
        if original_result is None:
            RESULT_FILE.unlink(missing_ok=True)
        else:
            RESULT_FILE.write_bytes(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
