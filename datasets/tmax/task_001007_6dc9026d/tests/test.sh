#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import ssl
import sys
import hashlib
import subprocess
import datetime
import pytest
from pathlib import Path
from cryptography.fernet import Fernet
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa


def test_secure_report_exists():
    """Verify that the secure report was generated."""
    report_path = '/home/user/secure_report.html'
    assert os.path.isfile(report_path), f"The secure report file was not found at {report_path}."


def test_report_contents():
    """Verify that the secure report contains the correct CSP, integrity status, fingerprint, and config."""
    report_path = '/home/user/secure_report.html'
    assert os.path.isfile(report_path), "Cannot verify contents because secure_report.html is missing."

    with open(report_path, 'r', encoding='utf-8') as f:
        content = f.read()

    expected_csp = """<meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'none';">"""
    assert expected_csp in content, "The required exact Content-Security-Policy meta tag is missing."
    assert "Integrity: OK" in content, "The string 'Integrity: OK' is missing from the report."

    expected_config = '{"db_host": "secure-db.local", "port": 5432, "feature_flag": true}'
    assert expected_config in content, "The decrypted configuration plaintext is missing from the report."

    cert_path = '/home/user/server.crt'
    assert os.path.isfile(cert_path), f"Certificate file missing at {cert_path}."
    with open(cert_path, 'r') as f:
        pem_data = f.read()

    der_data = ssl.PEM_cert_to_DER_cert(pem_data)
    fingerprint_hex = hashlib.sha256(der_data).hexdigest()
    expected_fingerprint = ':'.join(fingerprint_hex[i:i+2] for i in range(0, len(fingerprint_hex), 2))
    assert expected_fingerprint in content, f"The expected certificate fingerprint ({expected_fingerprint}) is missing from the report."


def test_deploy_script_no_args():
    """Verify that the refactored script no longer uses sys.argv[1] for the key."""
    script_path = '/home/user/deploy.py'
    assert os.path.isfile(script_path), f"Script missing: {script_path}"

    with open(script_path, 'r') as f:
        content = f.read()

    assert "sys.argv[1]" not in content, "The deploy.py script still appears to read from sys.argv[1]."


def test_dynamic_execution_and_integrity_failure():
    """Execute deploy.py against fresh inputs and verify success and hash-mismatch behavior."""
    paths = [
        Path('/home/user/.secret_key'),
        Path('/home/user/config.enc'),
        Path('/home/user/config.sha256'),
        Path('/home/user/server.crt'),
        Path('/home/user/secure_report.html'),
    ]
    backups = {path: path.read_bytes() if path.exists() else None for path in paths}

    try:
        token = os.urandom(16).hex()
        plaintext = ('{"dynamic_test": "' + token + '", "enabled": true}').encode('utf-8')
        key = Fernet.generate_key()
        Path('/home/user/.secret_key').write_bytes(key)
        Path('/home/user/config.enc').write_bytes(Fernet(key).encrypt(plaintext))
        expected_hash = hashlib.sha256(plaintext).hexdigest()
        Path('/home/user/config.sha256').write_text(expected_hash, encoding='utf-8')

        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'dynamic-' + token + '.local')])
        cert = (
            x509.CertificateBuilder()
            .subject_name(name)
            .issuer_name(name)
            .public_key(private_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.datetime.utcnow() - datetime.timedelta(minutes=1))
            .not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=1))
            .sign(private_key, hashes.SHA256())
        )
        cert_pem = cert.public_bytes(serialization.Encoding.PEM)
        Path('/home/user/server.crt').write_bytes(cert_pem)
        expected_fingerprint = ':'.join(f'{b:02x}' for b in cert.fingerprint(hashes.SHA256()))

        report = Path('/home/user/secure_report.html')
        report.unlink(missing_ok=True)
        result = subprocess.run(
            [sys.executable, '/home/user/deploy.py'],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f'deploy.py failed with no arguments (status {result.returncode}): '
            f'{result.stderr.decode(errors="replace")}'
        )
        assert report.is_file(), 'deploy.py did not regenerate secure_report.html.'
        content = report.read_text(encoding='utf-8')
        expected_csp = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self'; script-src 'none';\">"
        assert expected_csp in content, 'Regenerated report is missing the exact required CSP meta tag.'
        assert 'Integrity: OK' in content, 'Regenerated report is missing Integrity: OK.'
        assert f'Cert Fingerprint: {expected_fingerprint}' in content, 'Regenerated report has the wrong certificate fingerprint.'
        assert f'Config: {plaintext.decode("utf-8")}' in content, 'Regenerated report does not contain the freshly decrypted plaintext.'

        wrong_hash = '0' * 64 if expected_hash != '0' * 64 else '1' * 64
        Path('/home/user/config.sha256').write_text(wrong_hash, encoding='utf-8')
        report.unlink(missing_ok=True)
        mismatch = subprocess.run(
            [sys.executable, '/home/user/deploy.py'],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert mismatch.returncode == 1, f'Hash mismatch must exit with status 1, got {mismatch.returncode}.'
        assert not report.exists(), 'A report was generated despite the configuration hash mismatch.'
    finally:
        for path, data in backups.items():
            if data is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
