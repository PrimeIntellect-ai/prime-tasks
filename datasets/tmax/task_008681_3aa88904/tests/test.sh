#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
DEPLOY = HOME / 'deploy'
SOURCE = HOME / 'rotate_cli.cpp'
BINARY = HOME / 'rotate_cli'


def run_checked(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {args}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


def openssl(*args):
    return run_checked(['openssl', *args])


def test_cwe_report():
    report_path = HOME / 'cwe_report.txt'
    assert report_path.is_file(), f"File missing: {report_path}"

    content = report_path.read_text().upper()
    assert 'CWE-78' in content, 'CWE-78 (OS Command Injection) missing from report'
    assert 'CWE-79' in content, 'CWE-79 (Cross-Site Scripting) missing from report'

    normalized = content.strip()
    assert re.fullmatch(r'CWE-(?:78|79)\s*,\s*CWE-(?:78|79)', normalized), \
        'Report must contain only the two comma-separated CWE IDs'
    ids = [item.strip() for item in normalized.split(',')]
    assert set(ids) == {'CWE-78', 'CWE-79'} and len(ids) == 2


def test_certificates():
    cert_path = HOME / 'new_cert.pem'
    key_path = HOME / 'new_key.pem'

    assert cert_path.is_file(), f"Certificate missing: {cert_path}"
    assert key_path.is_file(), f"Key missing: {key_path}"

    # Preserve the original subject assertion.
    result = subprocess.run(
        ['openssl', 'x509', '-in', str(cert_path), '-noout', '-subject'],
        capture_output=True, text=True
    )
    assert result.returncode == 0, 'Failed to parse certificate'
    assert 'CN' in result.stdout and 'localhost' in result.stdout, \
        'Certificate Subject CN is not localhost'

    # Preserve the original RSA-key assertion.
    result_key = subprocess.run(
        ['openssl', 'rsa', '-in', str(key_path), '-check', '-noout'],
        capture_output=True, text=True
    )
    assert result_key.returncode == 0, 'Key is not a valid RSA key'

    subject = openssl('x509', '-in', str(cert_path), '-noout', '-subject',
                      '-nameopt', 'RFC2253').stdout.strip()
    issuer = openssl('x509', '-in', str(cert_path), '-noout', '-issuer',
                     '-nameopt', 'RFC2253').stdout.strip()
    subject_dn = subject.split('=', 1)[1].strip()
    issuer_dn = issuer.split('=', 1)[1].strip()
    assert subject_dn == issuer_dn, 'Certificate issuer and subject differ; it is not self-signed'
    assert re.findall(r'(?:^|,)CN=([^,]+)', subject_dn) == ['localhost'], \
        'Certificate must have exactly one Subject CN equal to localhost'

    verify = subprocess.run(
        ['openssl', 'verify', '-check_ss_sig', '-CAfile', str(cert_path), str(cert_path)],
        capture_output=True, text=True
    )
    assert verify.returncode == 0, f'Certificate self-signature verification failed: {verify.stderr}'

    dates = openssl('x509', '-in', str(cert_path), '-noout', '-dates').stdout.splitlines()
    parsed = dict(line.split('=', 1) for line in dates)
    fmt = '%b %d %H:%M:%S %Y %Z'
    not_before = datetime.datetime.strptime(parsed['notBefore'], fmt)
    not_after = datetime.datetime.strptime(parsed['notAfter'], fmt)
    assert not_after - not_before == datetime.timedelta(days=365), \
        'Certificate validity interval is not exactly 365 days'

    cert_pub = subprocess.run(
        ['openssl', 'x509', '-in', str(cert_path), '-pubkey', '-noout'],
        capture_output=True, check=True
    ).stdout
    cert_pub_der = subprocess.run(
        ['openssl', 'pkey', '-pubin', '-outform', 'DER'],
        input=cert_pub, capture_output=True, check=True
    ).stdout
    key_pub_der = subprocess.run(
        ['openssl', 'pkey', '-in', str(key_path), '-pubout', '-outform', 'DER'],
        capture_output=True, check=True
    ).stdout
    assert cert_pub_der == key_pub_der, 'Certificate does not match the supplied private key'

    key_text = openssl('rsa', '-in', str(key_path), '-text', '-noout').stdout
    assert re.search(r'(?:Private-Key|RSA Private-Key): \(2048 bit', key_text), \
        'Private key is not RSA 2048-bit'


def test_code_changes(tmp_path):
    assert SOURCE.is_file(), f"File missing: {SOURCE}"
    assert BINARY.is_file(), f"Compiled binary missing: {BINARY}"

    content = SOURCE.read_text()
    assert 'system(' not in content, 'Vulnerable system() call still present in C++ code'
    assert '<filesystem>' in content, 'Missing #include <filesystem> in C++ code'

    assert os.access(BINARY, os.X_OK), 'Compiled binary is not executable'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'rotate_cli is not a compiled ELF binary'

    rebuilt = tmp_path / 'rotate_cli_rebuilt'
    compile_result = subprocess.run(
        ['g++', '-std=c++17', str(SOURCE), '-o', str(rebuilt)],
        capture_output=True, text=True
    )
    assert compile_result.returncode == 0, f'Secured source does not compile: {compile_result.stderr}'


# Preserve the original fixed functional assertions.
def test_original_functional_verification():
    cert_path = HOME / 'new_cert.pem'
    key_path = HOME / 'new_key.pem'

    xss_payload = '<script>alert(1)</script>'
    subprocess.run([str(BINARY), str(cert_path), str(key_path), xss_payload], capture_output=True)

    status_file = DEPLOY / 'status.html'
    assert status_file.is_file(), f"Status report missing: {status_file}"
    status_content = status_file.read_text()
    assert '<script>' not in status_content, \
        'XSS vulnerability still present: <script> tag found in HTML output'
    assert '&lt;script&gt;' in status_content, \
        'XSS mitigation failed: payload was not properly HTML-encoded'

    pwned_file = HOME / 'pwned'
    if pwned_file.exists():
        pwned_file.unlink()
    cmd_payload = 'test; touch /home/user/pwned'
    subprocess.run([str(BINARY), cmd_payload, str(key_path), 'msg'], capture_output=True)
    assert not pwned_file.exists(), \
        'Command injection vulnerability still present: arbitrary command executed'


def encoded(value):
    return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def exercise(binary, tmp_path, tag):
    token = secrets.token_hex(18)
    inputs = tmp_path / f'input dir {token}'
    inputs.mkdir()
    cert = inputs / f'cert ; unusual & {token}.pem'
    key = inputs / f'key $ unusual {token}.pem'
    cert_bytes = secrets.token_bytes(257) + token.encode()
    key_bytes = secrets.token_bytes(311) + token[::-1].encode()
    cert.write_bytes(cert_bytes)
    key.write_bytes(key_bytes)

    status = f'{tag}-{token}<&>middle&tail<{secrets.token_hex(8)}>'
    result = subprocess.run(
        [str(binary), str(cert), str(key), status],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f'Utility failed on valid paths: {result.stderr}'
    assert (DEPLOY / 'cert.pem').read_bytes() == cert_bytes, \
        'Certificate was not copied byte-for-byte to deploy/cert.pem'
    assert (DEPLOY / 'key.pem').read_bytes() == key_bytes, \
        'Key was not copied byte-for-byte to deploy/key.pem'

    expected = f'<html><body><h1>Rotation Status</h1><p>{encoded(status)}</p></body></html>'
    assert (DEPLOY / 'status.html').read_text() == expected, \
        'Status report did not correctly encode all of <, >, and &'

    marker = HOME / f'injection_{secrets.token_hex(12)}'
    innocent = inputs / 'innocent'
    innocent.write_bytes(b'innocent')
    malicious_path = f'{innocent}; touch {marker}; #'
    subprocess.run([str(binary), malicious_path, str(key), status], capture_output=True, text=True)
    assert not marker.exists(), 'A metacharacter-bearing path executed an OS command'


def test_randomized_deployment_and_encoding(tmp_path):
    rebuilt = tmp_path / 'rebuilt_cli'
    run_checked(['g++', '-std=c++17', str(SOURCE), '-o', str(rebuilt)])
    exercise(BINARY, tmp_path, 'submitted-binary')
    exercise(rebuilt, tmp_path, 'rebuilt-source')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
