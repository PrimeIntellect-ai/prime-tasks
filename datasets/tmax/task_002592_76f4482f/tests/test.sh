#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import shutil
import subprocess
import tempfile
import uuid

import pytest


def run_checked(command):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=True,
    )


def test_ca_chain_exists_and_valid():
    chain_path = '/home/user/certs/ca-chain.pem'
    assert os.path.isfile(chain_path), f"File {chain_path} is missing."

    with open(chain_path, 'r') as f:
        chain_content = f.read()

    cert_count = chain_content.count('BEGIN CERTIFICATE')
    assert cert_count >= 2, f"ca-chain.pem should contain at least root and intermediate certs, found {cert_count}."

    required = [
        '/home/user/certs/rootCA.pem',
        '/home/user/certs/rootCA.key',
        '/home/user/certs/intermediateCA.pem',
        '/home/user/certs/intermediateCA.key',
        '/home/user/certs/client_valid.pem',
        '/home/user/certs/client_valid.key',
        '/home/user/certs/client_invalid.pem',
    ]
    for path in required:
        assert os.path.isfile(path), f"Required PKI artifact missing: {path}"

    run_checked([
        'openssl', 'verify',
        '-CAfile', '/home/user/certs/rootCA.pem',
        '/home/user/certs/intermediateCA.pem',
    ])
    run_checked([
        'openssl', 'verify',
        '-CAfile', '/home/user/certs/rootCA.pem',
        '-untrusted', '/home/user/certs/intermediateCA.pem',
        '/home/user/certs/client_valid.pem',
    ])

    invalid = subprocess.run(
        ['openssl', 'verify', '-CAfile', chain_path, '/home/user/certs/client_invalid.pem'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert invalid.returncode != 0, 'client_invalid.pem unexpectedly validates against the trusted chain.'


def test_audit_tool_binary():
    tool_path = '/home/user/audit_tool'
    assert os.path.isfile('/home/user/audit_tool.c'), 'audit_tool.c is missing.'
    assert os.path.isfile(tool_path), f"audit_tool binary missing at {tool_path}."
    assert os.access(tool_path, os.X_OK), f"audit_tool at {tool_path} is not executable."

    try:
        output = subprocess.check_output(['ldd', tool_path], stderr=subprocess.STDOUT).decode()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run ldd on {tool_path}: {e.output.decode()}")

    assert 'libcrypto' in output, "audit_tool is not linked to libcrypto."


@pytest.fixture(scope='module')
def fresh_certificates():
    with tempfile.TemporaryDirectory(prefix='audit-verifier-') as tempdir:
        valid_key = os.path.join(tempdir, uuid.uuid4().hex + '.key')
        valid_csr = os.path.join(tempdir, uuid.uuid4().hex + '.csr')
        valid_cert = os.path.join(tempdir, uuid.uuid4().hex + '.pem')
        invalid_key = os.path.join(tempdir, uuid.uuid4().hex + '.key')
        invalid_cert = os.path.join(tempdir, uuid.uuid4().hex + '.pem')
        extensions = os.path.join(tempdir, 'client.ext')

        with open(extensions, 'w') as f:
            f.write('basicConstraints=critical,CA:FALSE\n')
            f.write('keyUsage=critical,digitalSignature,keyEncipherment\n')
            f.write('extendedKeyUsage=clientAuth\n')

        run_checked([
            'openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes',
            '-subj', '/CN=' + secrets.token_hex(12),
            '-keyout', valid_key, '-out', valid_csr,
        ])
        run_checked([
            'openssl', 'x509', '-req', '-in', valid_csr,
            '-CA', '/home/user/certs/intermediateCA.pem',
            '-CAkey', '/home/user/certs/intermediateCA.key',
            '-set_serial', str(secrets.randbelow(2**62) + 1),
            '-days', '2', '-sha256', '-extfile', extensions,
            '-out', valid_cert,
        ])
        run_checked([
            'openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
            '-subj', '/CN=' + secrets.token_hex(12),
            '-days', '2', '-sha256',
            '-keyout', invalid_key, '-out', invalid_cert,
        ])

        run_checked([
            'openssl', 'verify',
            '-CAfile', '/home/user/certs/rootCA.pem',
            '-untrusted', '/home/user/certs/intermediateCA.pem',
            valid_cert,
        ])
        rogue_check = subprocess.run(
            ['openssl', 'verify', '-CAfile', '/home/user/certs/ca-chain.pem', invalid_cert],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert rogue_check.returncode != 0
        yield valid_cert, invalid_cert, tempdir


def b64url_json(value):
    raw = json.dumps(value, separators=(',', ':')).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip('=')


def invoke_tool(request_path, certificate_path):
    result = subprocess.run(
        ['/home/user/audit_tool', request_path, certificate_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, f'Expected exactly one audit output line; stdout={result.stdout!r}, stderr={result.stderr!r}'
    return lines[0]


def test_audit_tool_behavior_on_fresh_inputs(fresh_certificates):
    valid_cert, invalid_cert, tempdir = fresh_certificates
    nonce = secrets.token_hex(20)
    secure_header = b64url_json({'alg': 'HS256', 'nonce': nonce})
    none_header = b64url_json({'alg': 'none', 'nonce': nonce})
    secure_token = secure_header + '.' + secrets.token_urlsafe(13) + '.' + secrets.token_urlsafe(11)
    none_token = none_header + '.' + secrets.token_urlsafe(13) + '.' + secrets.token_urlsafe(11)

    cases = [
        (invalid_cert, none_token, '<script>' + nonce + '</script>', 'AUDIT: [REJECT] Cert invalid'),
        (valid_cert, none_token, '<script>' + nonce + '</script>', 'AUDIT: [REJECT] Insecure algorithm'),
        (valid_cert, secure_token, 'prefix-' + nonce + '-<script>alert(1);</script>-suffix', 'AUDIT: [REJECT] XSS detected'),
        (valid_cert, secure_token, 'safe body ' + nonce, 'AUDIT: [PASS] Request accepted'),
    ]

    for certificate, token, body, expected in cases:
        request_path = os.path.join(tempdir, uuid.uuid4().hex + '.request')
        request = (
            'POST /' + secrets.token_hex(7) + ' HTTP/1.1\n'
            'Host: offline-' + secrets.token_hex(5) + '\n'
            'Authorization: Bearer ' + token + '\n'
            'X-Audit-Nonce: ' + nonce + '\n\n' + body + '\n'
        )
        with open(request_path, 'w') as f:
            f.write(request)
        assert invoke_tool(request_path, certificate) == expected

    header_xss_request = os.path.join(tempdir, uuid.uuid4().hex + '.request')
    with open(header_xss_request, 'w') as f:
        f.write(
            'GET / HTTP/1.1\n'
            'Authorization: Bearer ' + secure_token + '\n'
            'X-Probe: before<script>after\n\n'
            'safe body ' + nonce + '\n'
        )
    assert invoke_tool(header_xss_request, valid_cert) == 'AUDIT: [REJECT] XSS detected'


def test_audit_trail_log():
    script_path = '/home/user/run_audit.sh'
    log_path = '/home/user/audit_trail.log'
    assert os.path.isfile(script_path), f"run_audit.sh missing at {script_path}."

    os.makedirs('/home/user/requests', exist_ok=True)
    for name in ('req1.txt', 'req2.txt', 'req3.txt', 'req4.txt'):
        path = os.path.join('/home/user/requests', name)
        if os.path.exists(path):
            os.remove(path)
    if os.path.exists(log_path):
        os.remove(log_path)

    result = subprocess.run(
        ['bash', script_path],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"run_audit.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
    for name in ('req1.txt', 'req2.txt', 'req3.txt', 'req4.txt'):
        assert os.path.isfile(os.path.join('/home/user/requests', name)), f'{name} was not created.'

    assert os.path.isfile(log_path), f"audit_trail.log missing at {log_path}."

    with open(log_path, 'r') as f:
        log_content = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    expected = [
        "Test 1:",
        "AUDIT: [REJECT] Cert invalid",
        "Test 2:",
        "AUDIT: [REJECT] Insecure algorithm",
        "Test 3:",
        "AUDIT: [REJECT] XSS detected",
        "Test 4:",
        "AUDIT: [PASS] Request accepted"
    ]

    assert len(log_content) == len(expected), f"Expected {len(expected)} lines in log, got {len(log_content)}."

    for i, (actual, exp) in enumerate(zip(log_content, expected)):
        assert actual == exp, f"Line {i+1} mismatch. Expected: '{exp}', Got: '{actual}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
