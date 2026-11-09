#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import hashlib
import hmac
import importlib.metadata
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import sys
from urllib.parse import unquote, urlparse

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

IMPLANT = Path('/home/user/evidence/implant.bin')
VENDORED = Path('/app/vendored/pyjwt-2.8.0').resolve()
C2_URL = 'https://127.0.0.1:8443/beacon'


def extract_artifacts():
    data = IMPLANT.read_bytes()

    cert_begin = data.index(b'-----BEGIN CERTIFICATE-----')
    cert_end = data.index(b'-----END CERTIFICATE-----', cert_begin) + len(b'-----END CERTIFICATE-----')
    cert_pem = data[cert_begin:cert_end] + b'\n'

    key_begin = data.index(b'-----BEGIN PRIVATE KEY-----')
    key_end = data.index(b'-----END PRIVATE KEY-----', key_begin) + len(b'-----END PRIVATE KEY-----')
    key_pem = data[key_begin:key_end] + b'\n'

    secret = data.split(b'JWT_SECRET:', 1)[1].splitlines()[0].decode('utf-8')
    payload = data.split(b'C2_PAYLOAD:', 1)[1].splitlines()[0].decode('utf-8')
    return cert_pem, key_pem, secret, payload


CERT_PEM, KEY_PEM, SECRET, PAYLOAD = extract_artifacts()
EXPECTED_PAYLOAD = {'status': 'ok', 'payload': PAYLOAD}


def b64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=')


def make_hs256_token(claims, secret):
    header = b64url(json.dumps({'alg': 'HS256', 'typ': 'JWT'}, separators=(',', ':'), sort_keys=True).encode())
    body = b64url(json.dumps(claims, separators=(',', ':'), sort_keys=True).encode())
    signing_input = header + b'.' + body
    signature = hmac.new(secret.encode(), signing_input, hashlib.sha256).digest()
    return (signing_input + b'.' + b64url(signature)).decode()


def make_none_token(claims):
    header = b64url(json.dumps({'alg': 'none', 'typ': 'JWT'}, separators=(',', ':')).encode())
    body = b64url(json.dumps(claims, separators=(',', ':')).encode())
    return (header + b'.' + body + b'.').decode()


def request(token=None, authorization=None):
    headers = {}
    if token is not None:
        headers['Authorization'] = 'Bearer ' + token
    elif authorization is not None:
        headers['Authorization'] = authorization
    try:
        return requests.get(C2_URL, headers=headers, verify=False, timeout=5)
    except requests.exceptions.ConnectionError as exc:
        pytest.fail(f'Could not connect to C2 server at {C2_URL}: {exc}')


def assert_valid(token):
    response = request(token=token)
    assert response.status_code == 200, (
        f'Expected HTTP 200 for valid token, got {response.status_code}: {response.text}'
    )
    try:
        actual = response.json()
    except ValueError:
        pytest.fail(f'Expected JSON response, got: {response.text}')
    assert actual == EXPECTED_PAYLOAD


def assert_unauthorized(token=None, authorization=None):
    response = request(token=token, authorization=authorization)
    assert response.status_code == 401, (
        f'Expected HTTP 401, got {response.status_code}: {response.text}'
    )


def test_server_is_bound_exactly_to_ipv4_loopback():
    expected = '0100007F:20FB'
    listeners = []
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        for line in Path(table).read_text().splitlines()[1:]:
            fields = line.split()
            if fields[3] == '0A' and fields[1].upper().endswith(':20FB'):
                listeners.append(fields[1].upper())
    assert expected in listeners, f'No listener found on exactly 127.0.0.1:8443; found {listeners}'
    assert listeners == [expected], f'Port 8443 must listen only on 127.0.0.1; found {listeners}'


def test_server_uses_embedded_tls_certificate_and_corresponding_key():
    expected_der = ssl.PEM_cert_to_DER_cert(CERT_PEM.decode())
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(('127.0.0.1', 8443), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname='127.0.0.1') as tls:
            peer_der = tls.getpeercert(binary_form=True)
    assert peer_der == expected_der, 'HTTPS server is not presenting the certificate embedded in implant.bin'
    # Completing the TLS handshake with that exact certificate also proves possession
    # of its corresponding private key. Ensure the embedded key was genuinely found.
    assert KEY_PEM.startswith(b'-----BEGIN PRIVATE KEY-----')


def test_vendored_pyjwt_was_repaired_and_installed():
    import jwt

    assert getattr(jwt, '__version__', None) == '2.8.0'

    api_jws = VENDORED / 'jwt' / 'api_jws.py'
    tree = ast.parse(api_jws.read_text())
    methods = [node for node in ast.walk(tree)
               if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
               and node.name == '_verify_signature']
    assert methods, 'Vendored api_jws.py has no _verify_signature implementation'
    assert methods[0].body and not isinstance(methods[0].body[0], ast.Raise), (
        'The unconditional signature-validation failure is still present'
    )

    imported_path = Path(jwt.__file__).resolve()
    installed_from_vendor = VENDORED in imported_path.parents
    try:
        dist = importlib.metadata.distribution('PyJWT')
        direct_url_text = dist.read_text('direct_url.json')
        if direct_url_text:
            source_url = json.loads(direct_url_text).get('url', '')
            parsed = urlparse(source_url)
            if parsed.scheme == 'file':
                source_path = Path(unquote(parsed.path)).resolve()
                installed_from_vendor = installed_from_vendor or source_path == VENDORED
    except importlib.metadata.PackageNotFoundError:
        pass
    assert installed_from_vendor, (
        f'Imported PyJWT was not installed from {VENDORED}; imported {imported_path}'
    )

    claims = {'test': 'data', 'nonce': secrets.token_hex(12)}
    token = make_hs256_token(claims, SECRET)
    assert jwt.decode(token, SECRET, algorithms=['HS256']) == claims
    with pytest.raises(jwt.exceptions.InvalidSignatureError):
        jwt.decode(token, secrets.token_hex(24), algorithms=['HS256'])

    script = '''
import pathlib, sys, jwt
assert pathlib.Path(jwt.__file__).resolve().is_relative_to(pathlib.Path(sys.argv[1]).resolve())
token, secret, expected = sys.argv[2:]
assert jwt.decode(token, secret, algorithms=["HS256"]) == {"probe": expected}
'''
    probe = secrets.token_hex(16)
    vendored_token = make_hs256_token({'probe': probe}, SECRET)
    env = dict(os.environ)
    env['PYTHONPATH'] = str(VENDORED)
    subprocess.run(
        [sys.executable, '-c', script, str(VENDORED), vendored_token, SECRET, probe],
        check=True, env=env, cwd='/tmp', timeout=10
    )


def test_c2_server_original_valid_token_case():
    assert_valid(make_hs256_token({'role': 'implant'}, SECRET))


def test_c2_server_validates_unpredictable_hs256_tokens():
    for index in range(4):
        claims = {
            'nonce': secrets.token_urlsafe(24),
            'sequence': secrets.randbelow(2**31),
            'nested': {'index': index, 'enabled': bool(index % 2)},
        }
        assert_valid(make_hs256_token(claims, SECRET))


def test_c2_server_original_wrong_secret_case():
    assert_unauthorized(token=make_hs256_token({'role': 'implant'}, 'wrong_secret_123'))


def test_c2_server_rejects_random_wrong_secrets_and_tampering():
    claims = {'nonce': secrets.token_urlsafe(30), 'value': secrets.randbelow(2**31)}
    for _ in range(3):
        assert_unauthorized(token=make_hs256_token(claims, secrets.token_urlsafe(32)))

    valid = make_hs256_token(claims, SECRET)
    header, body, signature_text = valid.split('.')
    padded = signature_text + '=' * (-len(signature_text) % 4)
    signature = bytearray(base64.urlsafe_b64decode(padded))
    signature[secrets.randbelow(len(signature))] ^= 1
    tampered = header + '.' + body + '.' + b64url(bytes(signature)).decode()
    assert_unauthorized(token=tampered)

    altered_claims = {'nonce': secrets.token_urlsafe(30), 'value': claims['value'] + 1}
    altered_body = b64url(json.dumps(altered_claims, separators=(',', ':'), sort_keys=True).encode()).decode()
    assert_unauthorized(token=header + '.' + altered_body + '.' + signature_text)


def test_c2_server_rejects_missing_and_malformed_authentication():
    assert_unauthorized()
    assert_unauthorized(authorization='Basic ' + secrets.token_urlsafe(20))
    assert_unauthorized(authorization='Bearer not.a.jwt')
    assert_unauthorized(token=make_none_token({'nonce': secrets.token_hex(16)}))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
