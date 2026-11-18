#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import datetime
import os
from pathlib import Path
import secrets
import subprocess

import pytest
from Crypto.Cipher import AES
from PIL import Image, ImageDraw
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

AGENT_SCRIPT = Path('/home/user/decode_payload.py')
ORACLE_PATH = Path('/app/oracle_decoder')
KEY_IMAGE = Path('/app/secret_key.png')
CERT_DIR = Path('/app/certs')
TEST_KEY_TEXT = 'RPT73_SECRET_KEY'
TEST_KEY = TEST_KEY_TEXT.encode('ascii')


def make_certificate(path, serial, not_before, not_after):
    key = rsa.generate_private_key(public_exponent=65537, key_size=1024)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'VerifierTest')])
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(serial)
        .not_valid_before(not_before)
        .not_valid_after(not_after)
        .sign(key, hashes.SHA256())
    )
    path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))


@pytest.fixture(scope='session', autouse=True)
def verification_material():
    original_image = KEY_IMAGE.read_bytes()
    valid_path = CERT_DIR / '.verifier_valid_cert.pem'
    expired_path = CERT_DIR / '.verifier_expired_cert.pem'

    valid_serial = secrets.randbits(120) | 1
    expired_serial = secrets.randbits(120) | 1
    while expired_serial == valid_serial:
        expired_serial = secrets.randbits(120) | 1

    now = datetime.datetime.utcnow()
    make_certificate(valid_path, valid_serial, now - datetime.timedelta(minutes=5),
                     now + datetime.timedelta(days=2))
    make_certificate(expired_path, expired_serial, now - datetime.timedelta(days=3),
                     now - datetime.timedelta(days=1))

    image = Image.new('RGB', (400, 100), color=(255, 255, 255))
    draw = ImageDraw.Draw(image)
    draw.text((10, 10), TEST_KEY_TEXT, fill=(0, 0, 0))
    image.save(KEY_IMAGE)

    yield {'valid_serial': valid_serial, 'expired_serial': expired_serial}

    KEY_IMAGE.write_bytes(original_image)
    valid_path.unlink(missing_ok=True)
    expired_path.unlink(missing_ok=True)


def run_agent(log_line):
    proc = subprocess.run(
        ['python3', str(AGENT_SCRIPT), log_line],
        capture_output=True,
        text=True,
        timeout=8,
    )
    return proc.stdout.strip()


def encrypt_token(command, raw_plaintext=False):
    plaintext = command if isinstance(command, bytes) else command.encode('utf-8')
    if not raw_plaintext:
        pad_len = 16 - (len(plaintext) % 16)
        plaintext += bytes([pad_len]) * pad_len
    assert len(plaintext) % 16 == 0

    while True:
        iv = os.urandom(16)
        ciphertext = AES.new(TEST_KEY, AES.MODE_CBC, iv).encrypt(plaintext)
        token = base64.b64encode(iv + ciphertext).decode('ascii')
        # Avoid ambiguity over whether an unescaped '+' in a URL is treated as
        # a literal Base64 character or form-encoding for a space.
        if '+' not in token:
            return token


def log_line(token, serial):
    return (
        '192.168.1.1 - - [10/Oct/2000:13:55:36 -0700] '
        f'"GET /shell?foo=1&token={token}&bar=2 HTTP/1.1" 200 2326 '
        f'X-Client-Serial: 0x{serial:X}'
    )


def test_required_python_artifact_exists():
    assert AGENT_SCRIPT.exists(), f'Agent script missing: {AGENT_SCRIPT}'
    assert AGENT_SCRIPT.is_file(), 'Agent submission is not a regular file'
    assert not AGENT_SCRIPT.is_symlink(), 'Agent submission must be a Python source file, not a symlink'
    assert ORACLE_PATH.exists(), f'Oracle missing: {ORACLE_PATH}'

    source_bytes = AGENT_SCRIPT.read_bytes()
    source = source_bytes.decode('utf-8')
    compile(source, str(AGENT_SCRIPT), 'exec')
    assert source_bytes != ORACLE_PATH.read_bytes(), 'Submission is byte-identical to the reference artifact'


@pytest.mark.parametrize('command', [
    'id',
    'cat /etc/passwd',
    'curl -fsS https://example.invalid/' + secrets.token_hex(8),
])
def test_valid_certificate_decrypts_payload(verification_material, command):
    token = encrypt_token(command)
    line = log_line(token, verification_material['valid_serial'])
    assert run_agent(line) == command


def test_unknown_certificate_is_rejected(verification_material):
    unknown = secrets.randbits(120) | 1
    while unknown in (verification_material['valid_serial'], verification_material['expired_serial']):
        unknown = secrets.randbits(120) | 1
    line = log_line(encrypt_token('whoami'), unknown)
    assert run_agent(line) == 'AUTH_FAILED'


def test_expired_certificate_is_rejected(verification_material):
    line = log_line(encrypt_token('hostname'), verification_material['expired_serial'])
    assert run_agent(line) == 'AUTH_FAILED'


@pytest.mark.parametrize('line', [
    '',
    'this is not an Apache access log line',
    '127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET /shell HTTP/1.1" 200 0 X-Client-Serial: 0x1',
    '127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET /shell?token=AAAA HTTP/1.1" 200 0',
])
def test_malformed_log_lines_report_error(line):
    assert run_agent(line) == 'ERROR'


def test_invalid_base64_or_ciphertext_reports_error(verification_material):
    serial = verification_material['valid_serial']
    assert run_agent(log_line('!!!!', serial)) == 'ERROR'
    short_payload = base64.b64encode(os.urandom(17)).decode('ascii')
    assert run_agent(log_line(short_payload, serial)) == 'ERROR'


def test_invalid_padding_reports_error(verification_material):
    # A complete AES block ending in 0x00 is never valid PKCS#7 padding.
    token = encrypt_token(b'A' * 15 + b'\x00', raw_plaintext=True)
    assert run_agent(log_line(token, verification_material['valid_serial'])) == 'ERROR'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
