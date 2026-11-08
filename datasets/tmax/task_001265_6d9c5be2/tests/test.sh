#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import urllib.request
import urllib.error
import pytest
import re
import base64
import hashlib
import json
import subprocess
import time
import uuid
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad

KEY = b'SuperSecretKey12'
DIRECT_URL = 'http://127.0.0.1:8083/validate'
GATEWAY_URL = 'http://127.0.0.1:8080/resource'


def encrypt_payload(payload, iv=None):
    if iv is None:
        iv = os.urandom(16)
    if isinstance(payload, str):
        payload = payload.encode('utf-8')
    ciphertext = AES.new(KEY, AES.MODE_CBC, iv).encrypt(pad(payload, AES.block_size))
    return base64.b64encode(iv + ciphertext).decode('ascii')


def make_token(user, role, checksum=None):
    if checksum is None:
        checksum = hashlib.md5((user + role).encode('utf-8')).hexdigest()
    payload = json.dumps({
        'user': user,
        'role': role,
        'checksum': checksum,
    }, separators=(',', ':'))
    return encrypt_payload(payload)


def make_bad_padding_token(user, role):
    raw = bytearray(base64.b64decode(make_token(user, role)))
    # Changing the last byte of the preceding CBC block changes the final
    # plaintext padding byte and deterministically invalidates PKCS#7 padding.
    raw[-17] ^= 1
    return base64.b64encode(raw).decode('ascii')


def request_status(url, token=None):
    req = urllib.request.Request(url)
    if token is not None:
        req.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.getcode(), response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except Exception as exc:
        pytest.fail(f'Request to {url} failed: {exc}')


nonce = uuid.uuid4().hex
VALID_CASES = [
    make_token('dynamic-user-' + nonce, 'user'),
    make_token('dynamic-viewer-' + nonce, 'viewer'),
    make_token('dynamic-admin-' + nonce, 'admin'),
]
BAD_CHECKSUM_TOKEN = make_token(
    'dynamic-bad-' + nonce,
    'admin',
    hashlib.md5(('dynamic-bad-' + nonce + 'user').encode()).hexdigest(),
)
MALFORMED_JSON_TOKEN = encrypt_payload('{"user":')
MISSING_FIELD_TOKEN = encrypt_payload(json.dumps({
    'user': 'missing-' + nonce,
    'role': 'user',
}))
BAD_PADDING_TOKEN = make_bad_padding_token('padding-' + nonce, 'user')
BAD_BASE64_TOKEN = 'not%%%base64-' + nonce
TRUNCATED_TOKEN = base64.b64encode(os.urandom(23)).decode('ascii')
INVALID_CASES = [
    BAD_CHECKSUM_TOKEN,
    MALFORMED_JSON_TOKEN,
    MISSING_FIELD_TOKEN,
    BAD_PADDING_TOKEN,
    BAD_BASE64_TOKEN,
    TRUNCATED_TOKEN,
]


def test_validator_binary_exists():
    assert os.path.isfile('/home/user/validator-bin'), "Validator binary /home/user/validator-bin is missing"
    assert os.access('/home/user/validator-bin', os.X_OK), "Validator binary is not executable"


def test_go_source_and_binary_are_real():
    source = '/home/user/validator/main.go'
    assert os.path.isfile(source), 'Go source /home/user/validator/main.go is missing'
    result = subprocess.run(
        ['go', 'build', '-o', '/tmp/validator-rebuilt', source],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f'Validator Go source does not compile: {result.stderr}'
    result = subprocess.run(
        ['go', 'version', '-m', '/home/user/validator-bin'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0 and 'go1.' in result.stdout, 'validator-bin is not a Go executable'


def test_validator_running():
    try:
        req = urllib.request.Request(DIRECT_URL)
        urllib.request.urlopen(req, timeout=2)
    except urllib.error.URLError as e:
        if not hasattr(e, 'code'):
            pytest.fail("Validator service is not running on port 8083")


def test_clean_corpus_accepted():
    clean_dir = '/app/corpus/clean'
    txt_files = glob.glob(os.path.join(clean_dir, '*.txt'))
    assert len(txt_files) > 0, "No clean tokens found"

    rejected = []
    for f in txt_files:
        with open(f, 'r') as file:
            token = file.read().strip()
        req = urllib.request.Request(DIRECT_URL)
        req.add_header('Authorization', f'Bearer {token}')
        try:
            res = urllib.request.urlopen(req, timeout=2)
            if res.getcode() != 200:
                rejected.append(os.path.basename(f))
        except urllib.error.HTTPError:
            rejected.append(os.path.basename(f))
        except Exception:
            rejected.append(os.path.basename(f))

    assert len(rejected) == 0, f"{len(rejected)} of {len(txt_files)} clean modified/rejected: {rejected[:5]}"


def test_evil_corpus_rejected():
    evil_dir = '/app/corpus/evil'
    txt_files = glob.glob(os.path.join(evil_dir, '*.txt'))
    assert len(txt_files) > 0, "No evil tokens found"

    bypassed = []
    for f in txt_files:
        with open(f, 'r') as file:
            token = file.read().strip()
        req = urllib.request.Request(DIRECT_URL)
        req.add_header('Authorization', f'Bearer {token}')
        try:
            res = urllib.request.urlopen(req, timeout=2)
            if res.getcode() == 200:
                bypassed.append(os.path.basename(f))
        except urllib.error.HTTPError as e:
            if e.code != 403:
                bypassed.append(f"{os.path.basename(f)} (returned {e.code})")
        except Exception:
            pass

    assert len(bypassed) == 0, f"{len(bypassed)} of {len(txt_files)} evil bypassed: {bypassed[:5]}"


def test_fresh_valid_tokens_accepted():
    for token in VALID_CASES:
        status, _ = request_status(DIRECT_URL, token)
        assert status == 200, f'Fresh valid token returned {status}, expected 200'


def test_fresh_invalid_tokens_rejected():
    labels = ['bad checksum', 'malformed JSON', 'missing field', 'bad padding', 'bad base64', 'invalid CBC length']
    for label, token in zip(labels, INVALID_CASES):
        status, _ = request_status(DIRECT_URL, token)
        assert status == 403, f'{label} token returned {status}, expected 403'


def test_nginx_configured_auth_request():
    conf_path = '/app/nginx/nginx.conf'
    assert os.path.isfile(conf_path), "Nginx config missing"
    with open(conf_path, 'r') as f:
        content = f.read()
    assert 'auth_request' in content, "auth_request directive not found in nginx.conf"
    assert '8083' in content or 'auth_validate' in content, "Validator service port 8083 or internal location not referenced in nginx.conf"


def test_end_to_end_nginx_proxy():
    clean_dir = '/app/corpus/clean'
    txt_files = glob.glob(os.path.join(clean_dir, '*.txt'))
    if not txt_files:
        pytest.fail("No clean tokens found for E2E test")

    with open(txt_files[0], 'r') as file:
        clean_token = file.read().strip()

    req = urllib.request.Request(GATEWAY_URL)
    req.add_header('Authorization', f'Bearer {clean_token}')
    try:
        res = urllib.request.urlopen(req, timeout=2)
        assert res.getcode() in [200, 404], f"Expected success or 404 from resource service, got {res.getcode()}"
    except urllib.error.HTTPError as e:
        if e.code == 403:
            pytest.fail("Nginx E2E test failed: clean token rejected by auth_request")

    evil_dir = '/app/corpus/evil'
    evil_files = glob.glob(os.path.join(evil_dir, '*.txt'))
    if not evil_files:
        pytest.fail("No evil tokens found for E2E test")

    with open(evil_files[0], 'r') as file:
        evil_token = file.read().strip()

    req = urllib.request.Request(GATEWAY_URL)
    req.add_header('Authorization', f'Bearer {evil_token}')
    try:
        urllib.request.urlopen(req, timeout=2)
        pytest.fail("Nginx E2E test failed: evil token bypassed auth_request")
    except urllib.error.HTTPError as e:
        assert e.code in [401, 403], f"Expected 401 or 403 for evil token, got {e.code}"


def test_fresh_tokens_end_to_end_through_nginx():
    status, body = request_status(GATEWAY_URL, VALID_CASES[2])
    assert status == 200, f'Gateway rejected a fresh valid token with status {status}'
    assert b'Resource Service' in body, 'Authorized /resource request was not proxied to the resource service'

    for token in (BAD_CHECKSUM_TOKEN, BAD_PADDING_TOKEN, MALFORMED_JSON_TOKEN):
        status, _ = request_status(GATEWAY_URL, token)
        assert status in (401, 403), f'Gateway allowed an invalid fresh token with status {status}'

    status, _ = request_status(GATEWAY_URL)
    assert status in (401, 403), f'Gateway allowed /resource without a token (status {status})'


def test_audit_log_exists():
    log_path = '/home/user/audit.log'
    assert os.path.isfile(log_path), "Audit log /home/user/audit.log is missing"
    with open(log_path, 'r') as f:
        content = f.read()
    assert "[ACCEPT]" in content or "[REJECT]" in content, "Audit log does not contain ACCEPT/REJECT entries"


def test_fresh_requests_are_audited_with_token_and_decision():
    log_path = '/home/user/audit.log'
    deadline = time.time() + 3
    content = ''
    while time.time() < deadline:
        if os.path.isfile(log_path):
            with open(log_path, 'r', errors='replace') as f:
                content = f.read()
        if (VALID_CASES[0] + ' - [ACCEPT]' in content and
                BAD_CHECKSUM_TOKEN + ' - [REJECT]' in content):
            break
        time.sleep(0.1)
    assert VALID_CASES[0] + ' - [ACCEPT]' in content, 'Fresh accepted token was not recorded in the required audit format'
    assert BAD_CHECKSUM_TOKEN + ' - [REJECT]' in content, 'Fresh rejected token was not recorded in the required audit format'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
