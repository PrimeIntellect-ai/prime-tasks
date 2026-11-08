#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
SOURCE = HOME / 'audit_scanner.cpp'
LOG = HOME / 'access.log'
REPORT = HOME / 'audit_report.csv'
PRIVATE_KEY = HOME / '.ssh/audit_key'
PUBLIC_KEY = HOME / '.ssh/audit_key.pub'

CANONICAL_CASES = [
    ('192.168.1.50', '/dashboard'),
    ('10.0.0.12', 'http://malicious.com/steal'),
    ('192.168.1.100', '/profile'),
    ('172.16.5.5', 'https://evil.org/phish'),
]


def expected_row(ip, url):
    return f'{ip},{url},{hashlib.sha256(url.encode("utf-8")).hexdigest()}'


def parse_output(data):
    text = data.decode('utf-8')
    lines = text.splitlines()
    assert all(line for line in lines), 'Scanner output contains blank lines.'
    for line in lines:
        fields = line.split(',')
        assert len(fields) == 3, f'Output is not strict three-column CSV: {line!r}'
        assert re.fullmatch(r'[0-9a-f]{64}', fields[2]), f'Invalid lowercase SHA-256 value: {fields[2]!r}'
    return lines


def test_audit_report_csv():
    assert REPORT.is_file(), f'File {REPORT} is missing.'
    assert LOG.is_file(), f'File {LOG} is missing.'

    expected_lines = [
        expected_row(ip, url)
        for ip, url in CANONICAL_CASES
        if url.startswith('http://') or url.startswith('https://')
    ]

    actual_lines = [line.strip() for line in REPORT.read_text().splitlines() if line.strip()]
    assert len(actual_lines) == len(expected_lines), (
        f'Expected {len(expected_lines)} lines in audit_report.csv, but found {len(actual_lines)}.'
    )
    for expected in expected_lines:
        assert expected in actual_lines, f"Expected line '{expected}' not found in audit_report.csv."
    assert actual_lines == expected_lines, 'audit_report.csv has incorrect ordering or extra content.'
    parse_output(REPORT.read_bytes())


def test_cpp_scanner_compiles_uses_openssl_and_handles_fresh_inputs():
    assert SOURCE.is_file(), f'File {SOURCE} is missing.'
    source_text = SOURCE.read_text()
    assert re.search(r'#\s*include\s*[<\"]openssl/', source_text), 'Scanner does not include OpenSSL headers.'

    with tempfile.TemporaryDirectory() as td:
        binary = Path(td) / 'audit_scanner'
        build = subprocess.run(
            ['g++', '-std=c++17', str(SOURCE), '-o', str(binary), '-lssl', '-lcrypto'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
        )
        assert build.returncode == 0, f'C++ scanner failed to compile:\n{build.stderr.decode(errors="replace")}'
        assert binary.is_file() and os.access(binary, os.X_OK), 'Compilation did not produce an executable.'

        nm = subprocess.run(
            ['nm', '-D', str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=True
        ).stdout.decode(errors='replace')
        assert re.search(r'\b(?:SHA256(?:_[A-Za-z0-9_]+)?|EVP_[A-Za-z0-9_]+)@', nm), (
            'Compiled scanner does not call an OpenSSL SHA-256/EVP API.'
        )

        original_log = LOG.read_bytes() if LOG.exists() else None
        nonce = secrets.token_hex(12)
        cases = [
            ('203.0.113.11', f'http://{nonce}.example/a?x=1&y=2', True, 'GET'),
            ('198.51.100.27', f'https://secure.example/{nonce}', True, 'GET'),
            ('192.0.2.44', f'http://example.net/{nonce}/again', True, 'GET'),
            ('203.0.113.12', f'/relative/{nonce}', False, 'GET'),
            ('203.0.113.13', f'HTTP://uppercase.example/{nonce}', False, 'GET'),
            ('203.0.113.14', f'ftp://example.org/{nonce}', False, 'GET'),
            ('203.0.113.15', f'xhttp://example.org/{nonce}', False, 'GET'),
            ('203.0.113.16', f'https://post.example/{nonce}', False, 'POST'),
        ]
        log_lines = [
            f'{ip} - - [12/Sep/2026:12:00:00 +0000] "{method} /login?redirect={url} HTTP/1.1" 302 123'
            for ip, url, _, method in cases
        ]
        log_lines.append(
            f'203.0.113.17 - - [12/Sep/2026:12:00:00 +0000] "GET /other?redirect=http://{nonce}.invalid HTTP/1.1" 200 10'
        )

        try:
            LOG.write_text('\n'.join(log_lines) + '\n')
            run = subprocess.run([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
            assert run.returncode == 0, f'Scanner exited with {run.returncode}: {run.stderr.decode(errors="replace")}'
            expected = [expected_row(ip, url) for ip, url, vulnerable, method in cases if vulnerable and method == 'GET']
            assert parse_output(run.stdout) == expected, 'Scanner produced incorrect output for fresh verifier-generated inputs.'

            canonical_lines = [
                f'{ip} - - [10/Oct/2023:13:55:36 +0000] "GET /login?redirect={url} HTTP/1.1" 302 512'
                for ip, url in CANONICAL_CASES
            ]
            canonical_lines.append(
                '10.0.0.15 - - [10/Oct/2023:14:05:00 +0000] "GET /about HTTP/1.1" 200 2048'
            )
            LOG.write_text('\n'.join(canonical_lines) + '\n')
            canonical_run = subprocess.run([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
            assert canonical_run.returncode == 0, 'Scanner failed on the audit log fixture.'
            canonical_expected = [
                expected_row(ip, url) for ip, url in CANONICAL_CASES
                if url.startswith('http://') or url.startswith('https://')
            ]
            assert parse_output(canonical_run.stdout) == canonical_expected, 'Compiled scanner does not generate the submitted report data.'
        finally:
            if original_log is None:
                LOG.unlink(missing_ok=True)
            else:
                LOG.write_bytes(original_log)


def test_ssh_key_generated():
    assert PRIVATE_KEY.is_file(), f'Private key file {PRIVATE_KEY} is missing.'
    assert PUBLIC_KEY.is_file(), f'Public key file {PUBLIC_KEY} is missing.'

    priv_content = PRIVATE_KEY.read_text()
    assert 'BEGIN OPENSSH PRIVATE KEY' in priv_content, (
        f'Private key {PRIVATE_KEY} does not appear to be a valid OpenSSH private key.'
    )
    pub_content = PUBLIC_KEY.read_text()
    assert 'ssh-ed25519' in pub_content, f'Public key {PUBLIC_KEY} does not appear to be an ed25519 key.'

    derived = subprocess.run(
        ['ssh-keygen', '-y', '-P', '', '-f', str(PRIVATE_KEY)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert derived.returncode == 0, (
        'Private key is invalid or does not have the required empty passphrase: '
        + derived.stderr.decode(errors='replace')
    )
    derived_fields = derived.stdout.decode().strip().split()
    public_lines = [line for line in pub_content.splitlines() if line.strip()]
    assert len(public_lines) == 1, 'Public key file must contain exactly one key.'
    public_fields = public_lines[0].split()
    assert len(derived_fields) >= 2 and derived_fields[0] == 'ssh-ed25519', 'Private key is not ed25519.'
    assert len(public_fields) >= 2 and public_fields[0] == 'ssh-ed25519', 'Public key is not ed25519.'
    assert public_fields[:2] == derived_fields[:2], 'Public key does not match the private key.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
