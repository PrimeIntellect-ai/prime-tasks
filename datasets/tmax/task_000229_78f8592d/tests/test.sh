#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import string
import subprocess
import tempfile


def find_legacy_key():
    matches = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                parts = [p.decode('utf-8', 'surrogateescape') for p in f.read().split(b'\0') if p]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        for i, arg in enumerate(parts[:-1]):
            if arg == '/usr/local/bin/legacy_auth.sh':
                matches.append(parts[i + 1])
    assert matches, 'legacy_auth.sh is not running with a secret key command-line argument'
    assert all(matches), 'legacy_auth.sh has an empty secret key argument'
    assert len(set(matches)) == 1, 'Found inconsistent secret keys in legacy_auth.sh processes'
    return matches[0]


def xor_decrypt(hex_data, key):
    encrypted = bytes.fromhex(hex_data)
    key_bytes = key.encode('utf-8')
    assert key_bytes, 'Secret key must not be empty'
    return bytes(value ^ key_bytes[i % len(key_bytes)] for i, value in enumerate(encrypted))


def run_decrypt(hex_data, key):
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', '/home/user/decrypt.sh', hex_data, key],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, f'decrypt.sh failed: {result.stderr.decode("utf-8", "replace")}'
    return result.stdout.rstrip(b'\r\n')


def test_decrypt_script_exists_and_executable():
    path = '/home/user/decrypt.sh'
    assert os.path.isfile(path), f'Missing script: {path}'
    assert os.access(path, os.X_OK), f'Script is not executable: {path}'


def test_decrypt_script_is_pure_bash():
    path = '/home/user/decrypt.sh'
    assert os.path.isfile(path), f'Missing script: {path}'

    with open(path, 'r', encoding='utf-8') as f:
        original = f.read()
    content = original.lower()

    assert 'python' not in content, 'The decryption script must be written in Bash, not Python.'
    assert 'ruby' not in content, 'The decryption script must be written in Bash, not Ruby.'
    assert 'perl' not in content, 'The decryption script must be written in Bash, not Perl.'
    first_line = original.splitlines()[0] if original.splitlines() else ''
    assert first_line.startswith('#!') and 'bash' in first_line.lower(), 'decrypt.sh must use a Bash shebang'


def test_certificate_and_signature_are_valid():
    with tempfile.TemporaryDirectory() as tmp:
        public_key = os.path.join(tmp, 'public_key.pem')
        extract = subprocess.run(
            ['openssl', 'x509', '-in', '/home/user/server.crt', '-pubkey', '-noout'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        assert extract.returncode == 0, f'Could not extract public key: {extract.stderr.decode("utf-8", "replace")}'
        assert b'BEGIN PUBLIC KEY' in extract.stdout, 'Certificate did not yield an RSA public key'
        with open(public_key, 'wb') as f:
            f.write(extract.stdout)

        verify = subprocess.run(
            ['openssl', 'dgst', '-sha256', '-verify', public_key,
             '-signature', '/home/user/token.sig', '/home/user/token.enc'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        assert verify.returncode == 0, f'RSA signature verification failed: {verify.stderr.decode("utf-8", "replace")}'
        assert b'Verified OK' in verify.stdout, 'OpenSSL did not report a valid signature'


def test_legacy_auth_process_exposes_key():
    find_legacy_key()


def test_decrypt_script_on_signed_token():
    key = find_legacy_key()
    with open('/home/user/token.enc', 'r', encoding='ascii') as f:
        encrypted_hex = f.read().strip()
    expected = xor_decrypt(encrypted_hex, key)
    assert run_decrypt(encrypted_hex, key) == expected, 'decrypt.sh did not correctly decrypt the signed token'


def test_decrypt_script_general_repeating_xor():
    alphabet = string.ascii_letters + string.digits + '_-'
    plaintext = ''.join(secrets.choice(alphabet) for _ in range(47)).encode('ascii')
    key = ''.join(secrets.choice(alphabet) for _ in range(13))
    key_bytes = key.encode('ascii')
    encrypted = bytes(value ^ key_bytes[i % len(key_bytes)] for i, value in enumerate(plaintext)).hex()
    assert run_decrypt(encrypted, key) == plaintext, 'decrypt.sh does not implement general repeating-key XOR decryption'


def test_decrypted_token_content():
    path = '/home/user/decrypted_token.txt'
    assert os.path.isfile(path), f'Missing decrypted token file: {path}'

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_plaintext = 'ACCESS_GRANTED_8839201_SYSTEM'
    assert content == expected_plaintext, f"Decrypted token content is incorrect. Expected '{expected_plaintext}', got '{content}'"


def test_decrypted_token_sha256_matches_expected_hash():
    with open('/home/user/decrypted_token.txt', 'rb') as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()
    with open('/home/user/expected_hash.txt', 'r', encoding='ascii') as f:
        expected_hash = f.read().strip().lower()
    assert actual_hash == expected_hash, f'SHA-256 mismatch: expected {expected_hash}, got {actual_hash}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
