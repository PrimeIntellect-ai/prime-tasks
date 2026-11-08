#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import datetime
import json
import os
import secrets
import subprocess
import uuid

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


def add_padding(b64_string):
    return b64_string + '=' * (-len(b64_string) % 4)


def run_script(script_path, output_path):
    assert os.path.isfile(script_path), f'Script {script_path} does not exist.'
    if os.path.exists(output_path):
        os.remove(output_path)
    result = subprocess.run(
        ['python3', script_path], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f'{script_path} failed to execute. Error: {result.stderr}'
    assert os.path.isfile(output_path), f'Script did not create {output_path}.'


def assert_ip_output(output_path, expected_ips):
    with open(output_path, 'r') as f:
        lines = f.readlines()
    found_ips = set(line.strip() for line in lines if line.strip())
    assert found_ips == expected_ips, f'The flagged IPs are incorrect. Expected {expected_ips}, but got {found_ips}.'
    assert len(lines) == len(found_ips), 'The flagged_ips.txt file should contain exactly one IP per line with no duplicates or blank lines.'


def test_task1_jwt_forgery():
    script_path = '/home/user/forge_jwt.py'
    assert os.path.isfile(script_path), f'Script {script_path} does not exist.'

    result = subprocess.run(['python3', script_path], capture_output=True, text=True)
    assert result.returncode == 0, f'forge_jwt.py failed to execute. Error: {result.stderr}'

    jwt_str = result.stdout.strip()
    parts = jwt_str.split('.')
    assert len(parts) == 3, f'Forged JWT must have exactly 3 parts separated by dots. Got {len(parts)} parts.'
    assert parts[2] == '', 'The signature part of the forged JWT must be empty.'

    try:
        header_bytes = base64.urlsafe_b64decode(add_padding(parts[0]))
        header = json.loads(header_bytes.decode('utf-8'))
    except Exception as e:
        pytest.fail(f'Could not decode or parse JWT header: {e}')

    try:
        payload_bytes = base64.urlsafe_b64decode(add_padding(parts[1]))
        payload = json.loads(payload_bytes.decode('utf-8'))
    except Exception as e:
        pytest.fail(f'Could not decode or parse JWT payload: {e}')

    assert header.get('alg', '').lower() == 'none', f"Header 'alg' must be 'none' (case-insensitive). Got: {header.get('alg')}"
    assert header.get('typ') == 'JWT', f"Header 'typ' must be 'JWT'. Got: {header.get('typ')}"
    assert payload.get('user') == 'admin', f"Payload 'user' must be 'admin'. Got: {payload.get('user')}"
    assert payload.get('role') == 'superuser', f"Payload 'role' must be 'superuser'. Got: {payload.get('role')}"


def encode_part(value):
    raw = json.dumps(value, separators=(',', ':')).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip('=')


def make_token(alg, payload, signature=''):
    return f'{encode_part({"alg": alg, "typ": "JWT"})}.{encode_part(payload)}.{signature}'


def random_ip(used):
    while True:
        ip = f'{secrets.randbelow(223) + 1}.{secrets.randbelow(256)}.{secrets.randbelow(256)}.{secrets.randbelow(254) + 1}'
        if ip not in used:
            used.add(ip)
            return ip


def test_task2_flagged_ips():
    script_path = '/home/user/detect_alg_none.py'
    log_path = '/home/user/access.log'
    output_path = '/home/user/flagged_ips.txt'
    assert os.path.isfile(script_path), f'Script {script_path} does not exist.'

    with open(log_path, 'rb') as f:
        original_log = f.read()

    try:
        run_script(script_path, output_path)
        assert_ip_output(output_path, {'10.0.0.5', '192.168.1.99'})

        used = set()
        flagged_a = random_ip(used)
        flagged_b = random_ip(used)
        safe_ip = random_ip(used)
        nonce = uuid.uuid4().hex
        none_a = make_token('NoNe', {'nonce': nonce, 'case': 1})
        none_b = make_token('NONE', {'nonce': nonce, 'case': 2})
        safe = make_token('HS256', {'nonce': nonce, 'case': 3}, 'random-signature')
        lines = [
            f'[2026-01-02 03:04:05] {safe_ip} GET /safe "Bearer {safe}"',
            f'[2026-01-02 03:04:06] {flagged_a} POST /admin "Bearer {none_a}"',
            f'[2026-01-02 03:04:07] {flagged_b} GET /settings "Bearer {none_b}"',
            f'[2026-01-02 03:04:08] {flagged_a} GET /again "Bearer {none_a}"',
        ]
        with open(log_path, 'w') as f:
            f.write('\n'.join(lines) + '\n')

        run_script(script_path, output_path)
        assert_ip_output(output_path, {flagged_a, flagged_b})
    finally:
        with open(log_path, 'wb') as f:
            f.write(original_log)
        subprocess.run(['python3', script_path], capture_output=True, text=True, timeout=30)


def generate_chain(valid_leaf):
    root_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    int_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    leaf_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    wrong_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    tag = uuid.uuid4().hex
    now = datetime.datetime.now(datetime.timezone.utc)

    def name(label):
        return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, f'{label}-{tag}')])

    def build(subject, issuer, public_key, signing_key, is_ca):
        builder = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(public_key)
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(minutes=1))
            .not_valid_after(now + datetime.timedelta(days=2))
            .add_extension(x509.BasicConstraints(ca=is_ca, path_length=None), critical=True)
        )
        return builder.sign(signing_key, hashes.SHA256())

    root_name = name('Root')
    int_name = name('Intermediate')
    leaf_name = name('Leaf')
    root_cert = build(root_name, root_name, root_key.public_key(), root_key, True)
    int_cert = build(int_name, root_name, int_key.public_key(), root_key, True)
    leaf_signer = int_key if valid_leaf else wrong_key
    leaf_cert = build(leaf_name, int_name, leaf_key.public_key(), leaf_signer, False)
    return b''.join(
        cert.public_bytes(serialization.Encoding.PEM)
        for cert in (leaf_cert, int_cert, root_cert)
    )


def read_status(path):
    with open(path, 'r') as f:
        return f.read().strip()


def test_task3_cert_status():
    script_path = '/home/user/validate_cert.py'
    chain_path = '/home/user/certs/server_chain.pem'
    status_path = '/home/user/cert_status.txt'
    assert os.path.isfile(script_path), f'Script {script_path} does not exist.'

    with open(chain_path, 'rb') as f:
        original_chain = f.read()

    try:
        run_script(script_path, status_path)
        content = read_status(status_path)
        assert content == 'INVALID', f"The certificate status is incorrect. Expected 'INVALID', but got '{content}'."

        cases = [(generate_chain(True), 'VALID'), (generate_chain(False), 'INVALID')]
        if secrets.randbelow(2):
            cases.reverse()
        for chain, expected in cases:
            with open(chain_path, 'wb') as f:
                f.write(chain)
            run_script(script_path, status_path)
            content = read_status(status_path)
            assert content == expected, f"The certificate status is incorrect. Expected '{expected}', but got '{content}'."
    finally:
        with open(chain_path, 'wb') as f:
            f.write(original_chain)
        subprocess.run(['python3', script_path], capture_output=True, text=True, timeout=30)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
