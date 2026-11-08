#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

INCIDENT = Path('/home/user/incident')
SOURCE = INCIDENT / 'investigate.c'
BINARY = INCIDENT / 'investigate'
OUTPUT = INCIDENT / 'redacted_payload.txt'
CHAIN = INCIDENT / 'c2_chain.pem'
ROOT = INCIDENT / 'root.pem'
CRYPTO = INCIDENT / 'crypto.txt'
TRAFFIC = INCIDENT / 'traffic.log'


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def make_certificates(directory):
    directory = Path(directory)
    root_cn = 'Root-' + secrets.token_hex(8)
    other_cn = 'Root-' + secrets.token_hex(8)

    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
         '-days', '30', '-keyout', str(directory / 'root.key'),
         '-out', str(directory / 'root.pem'), '-subj', f'/CN={root_cn}',
         '-addext', 'basicConstraints=critical,CA:TRUE',
         '-addext', 'keyUsage=critical,keyCertSign,cRLSign'])

    run(['openssl', 'req', '-newkey', 'rsa:2048', '-nodes',
         '-keyout', str(directory / 'int.key'),
         '-out', str(directory / 'int.csr'),
         '-subj', '/CN=VerifierIntermediate'])
    (directory / 'int.ext').write_text(
        '[ca]\n'
        'basicConstraints=critical,CA:TRUE,pathlen:0\n'
        'keyUsage=critical,keyCertSign,cRLSign\n'
        'subjectKeyIdentifier=hash\n'
        'authorityKeyIdentifier=keyid,issuer\n'
    )
    run(['openssl', 'x509', '-req', '-in', str(directory / 'int.csr'),
         '-CA', str(directory / 'root.pem'),
         '-CAkey', str(directory / 'root.key'), '-CAcreateserial',
         '-out', str(directory / 'int.pem'), '-days', '30',
         '-extfile', str(directory / 'int.ext'), '-extensions', 'ca'])

    run(['openssl', 'req', '-newkey', 'rsa:2048', '-nodes',
         '-keyout', str(directory / 'leaf.key'),
         '-out', str(directory / 'leaf.csr'),
         '-subj', '/CN=malicious-c2.local'])
    (directory / 'leaf.ext').write_text(
        '[leaf]\n'
        'basicConstraints=critical,CA:FALSE\n'
        'keyUsage=critical,digitalSignature,keyEncipherment\n'
        'subjectKeyIdentifier=hash\n'
        'authorityKeyIdentifier=keyid,issuer\n'
    )
    run(['openssl', 'x509', '-req', '-in', str(directory / 'leaf.csr'),
         '-CA', str(directory / 'int.pem'),
         '-CAkey', str(directory / 'int.key'), '-CAcreateserial',
         '-out', str(directory / 'leaf.pem'), '-days', '30',
         '-extfile', str(directory / 'leaf.ext'), '-extensions', 'leaf'])

    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
         '-days', '30', '-keyout', str(directory / 'other.key'),
         '-out', str(directory / 'other.pem'), '-subj', f'/CN={other_cn}',
         '-addext', 'basicConstraints=critical,CA:TRUE',
         '-addext', 'keyUsage=critical,keyCertSign,cRLSign'])

    chain = (directory / 'leaf.pem').read_bytes() + (directory / 'int.pem').read_bytes()
    return chain, (directory / 'root.pem').read_bytes(), (directory / 'other.pem').read_bytes()


def install_case(plaintext, cookie_first=False):
    key = secrets.token_bytes(16)
    iv = secrets.token_bytes(16)
    encrypted = run(
        ['openssl', 'enc', '-aes-128-cbc', '-K', key.hex(), '-iv', iv.hex()],
        input=plaintext
    ).stdout.hex()

    CRYPTO.write_text(f'KEY={key.hex()}\nIV={iv.hex()}\n')
    if cookie_first:
        cookie = f'session={encrypted}; other=value; theme=dark'
    else:
        cookie = f'other=value; session={encrypted}; theme=dark'
    TRAFFIC.write_text(
        'POST /api/v1/update HTTP/1.1\n'
        'Host: malicious-c2.local\n'
        'User-Agent: verifier-client\n'
        f'Cookie: {cookie}\n'
        'Content-Length: 0\n'
        'Connection: close\n\n'
    )


def execute_and_check(expected):
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run([str(BINARY)], cwd=str(INCIDENT),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=15)
    assert result.returncode == 0, (
        f'investigate exited with {result.returncode} on valid inputs. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert OUTPUT.is_file(), 'The program did not create redacted_payload.txt.'
    assert OUTPUT.read_bytes() == expected, (
        f'Incorrect program output. Expected {expected!r}, got {OUTPUT.read_bytes()!r}'
    )


def test_c_source_exists():
    assert os.path.isfile('/home/user/incident/investigate.c'), 'The C source file /home/user/incident/investigate.c does not exist.'


def test_compiled_binary_exists():
    assert os.path.isfile('/home/user/incident/investigate'), 'The compiled binary /home/user/incident/investigate does not exist. Did you compile it?'
    assert os.access('/home/user/incident/investigate', os.X_OK), 'The file /home/user/incident/investigate is not executable.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'The compiled artifact is not an ELF binary.'
    symbols = run(['nm', '-D', str(BINARY)]).stdout.decode('utf-8', 'replace')
    assert ('X509_verify_cert' in symbols and 'X509_STORE' in symbols), \
        'The binary does not reference OpenSSL certificate-chain validation APIs.'
    assert any(name in symbols for name in ('EVP_Decrypt', 'EVP_Cipher', 'AES_decrypt', 'AES_cbc_encrypt')), \
        'The binary does not reference an OpenSSL AES decryption API.'


def test_program_behavior():
    original = {p: p.read_bytes() for p in (CHAIN, ROOT, CRYPTO, TRAFFIC)}
    with tempfile.TemporaryDirectory() as td:
        valid_chain, valid_root, unrelated_root = make_certificates(td)
        try:
            CHAIN.write_bytes(valid_chain)
            ROOT.write_bytes(valid_root)

            marker1 = secrets.token_hex(12)
            plaintext1 = (
                f'{{"marker":"{marker1}","ssn":"123-45-6789",'
                f'"backup_ssn":"000-11-2222","role":"analyst"}}'
            ).encode()
            expected1 = re.sub(rb'\d{3}-\d{2}-\d{4}', b'***-**-****', plaintext1)
            install_case(plaintext1, cookie_first=False)
            execute_and_check(expected1)

            marker2 = secrets.token_hex(12)
            plaintext2 = (
                f'{{"username":"{marker2}","note":"no sensitive number here",'
                f'"ssn":"987-65-4321"}}'
            ).encode()
            expected2 = re.sub(rb'\d{3}-\d{2}-\d{4}', b'***-**-****', plaintext2)
            install_case(plaintext2, cookie_first=True)
            execute_and_check(expected2)

            ROOT.write_bytes(unrelated_root)
            if OUTPUT.exists():
                OUTPUT.unlink()
            invalid = subprocess.run([str(BINARY)], cwd=str(INCIDENT),
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     timeout=15)
            assert invalid.returncode == 1, (
                'The program must exit with status 1 when the certificate chain '
                f'is not trusted; it exited with {invalid.returncode}.'
            )
            assert (invalid.stdout + invalid.stderr).strip(), \
                'The program did not print an error for an invalid certificate chain.'

            ROOT.write_bytes(valid_root)
            final_plaintext = b'{"username":"sysadmin","session_id":"98765","ssn":"999-88-7777","role":"root"}'
            final_expected = b'{"username":"sysadmin","session_id":"98765","ssn":"***-**-****","role":"root"}'
            install_case(final_plaintext, cookie_first=True)
            execute_and_check(final_expected)
        finally:
            for path, contents in original.items():
                path.write_bytes(contents)


def test_redacted_payload_exists():
    assert os.path.isfile('/home/user/incident/redacted_payload.txt'), 'The output file /home/user/incident/redacted_payload.txt does not exist.'


def test_redacted_payload_content():
    expected_content = '{"username":"sysadmin","session_id":"98765","ssn":"***-**-****","role":"root"}'

    with open('/home/user/incident/redacted_payload.txt', 'r') as f:
        actual_content = f.read()

    assert actual_content == expected_content, f"The redacted payload content is incorrect.\nExpected: '{expected_content}'\nGot: '{actual_content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
