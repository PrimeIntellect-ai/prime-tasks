#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import secrets
import subprocess


def run(command):
    return subprocess.run(command, capture_output=True, text=True, timeout=30)


def test_certificate_and_key():
    cert_path = "/home/user/new_cert.pem"
    key_path = "/home/user/new_key.pem"

    assert os.path.isfile(cert_path), f"Certificate file {cert_path} does not exist."
    assert os.path.isfile(key_path), f"Private key file {key_path} does not exist."

    result = run(['openssl', 'x509', '-in', cert_path, '-noout', '-subject'])
    assert result.returncode == 0, f"Failed to read certificate with openssl. Error: {result.stderr}"

    subject = result.stdout.strip()
    assert "CN = test.local" in subject or "CN=test.local" in subject, \
        f"Certificate subject does not contain 'CN = test.local'. Actual subject: {subject}"

    canonical_subject = run([
        'openssl', 'x509', '-in', cert_path, '-noout', '-subject', '-nameopt', 'RFC2253'
    ])
    assert canonical_subject.returncode == 0, canonical_subject.stderr
    assert canonical_subject.stdout.strip() == "subject=CN=test.local", \
        f"Certificate must contain only CN=test.local; got: {canonical_subject.stdout.strip()}"

    canonical_issuer = run([
        'openssl', 'x509', '-in', cert_path, '-noout', '-issuer', '-nameopt', 'RFC2253'
    ])
    assert canonical_issuer.returncode == 0, canonical_issuer.stderr
    assert canonical_issuer.stdout.strip() == "issuer=CN=test.local", \
        f"Self-signed certificate has unexpected issuer: {canonical_issuer.stdout.strip()}"

    verify = run(['openssl', 'verify', '-check_ss_sig', '-CAfile', cert_path, cert_path])
    assert verify.returncode == 0, f"Certificate is not validly self-signed: {verify.stderr or verify.stdout}"

    key_check = run(['openssl', 'pkey', '-in', key_path, '-check', '-noout'])
    assert key_check.returncode == 0, f"Private key is invalid or unreadable: {key_check.stderr}"

    cert_pub = subprocess.run(
        ['openssl', 'x509', '-in', cert_path, '-pubkey', '-noout'],
        capture_output=True, timeout=30
    )
    assert cert_pub.returncode == 0, cert_pub.stderr.decode(errors='replace')
    rsa_details = subprocess.run(
        ['openssl', 'rsa', '-pubin', '-noout', '-text'],
        input=cert_pub.stdout, capture_output=True, timeout=30
    )
    assert rsa_details.returncode == 0, \
        f"Certificate public key is not RSA: {rsa_details.stderr.decode(errors='replace')}"
    details = rsa_details.stdout.decode(errors='replace')
    assert re.search(r'(?:Public-Key|Private-Key):\s*\(2048 bit\)', details), \
        f"Certificate RSA key is not 2048 bits: {details.splitlines()[:2]}"

    cert_pub_der = subprocess.run(
        ['openssl', 'pkey', '-pubin', '-outform', 'DER'],
        input=cert_pub.stdout, capture_output=True, timeout=30
    )
    key_pub_der = subprocess.run(
        ['openssl', 'pkey', '-in', key_path, '-pubout', '-outform', 'DER'],
        capture_output=True, timeout=30
    )
    assert cert_pub_der.returncode == 0, cert_pub_der.stderr.decode(errors='replace')
    assert key_pub_der.returncode == 0, key_pub_der.stderr.decode(errors='replace')
    assert cert_pub_der.stdout == key_pub_der.stdout, \
        "Private key does not match the certificate public key."

    dates = run(['openssl', 'x509', '-in', cert_path, '-noout', '-startdate', '-enddate'])
    assert dates.returncode == 0, dates.stderr
    values = dict(line.split('=', 1) for line in dates.stdout.splitlines() if '=' in line)
    assert 'notBefore' in values and 'notAfter' in values, f"Could not read validity: {dates.stdout}"
    fmt = '%b %d %H:%M:%S %Y %Z'
    not_before = datetime.datetime.strptime(values['notBefore'], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(values['notAfter'], fmt).replace(tzinfo=datetime.timezone.utc)
    assert not_after - not_before == datetime.timedelta(days=365), \
        f"Certificate validity is not exactly 365 days: {not_before} to {not_after}"
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."


def test_deploy_log_redacted():
    script_path = "/home/user/deploy_test.py"
    log_path = "/home/user/deploy.log"
    assert os.path.isfile(script_path), f"Deployment script {script_path} does not exist."

    if os.path.exists(log_path):
        os.remove(log_path)

    probe_password = "VerifierProbe-" + secrets.token_hex(16)
    probe_url = "https://probe-" + secrets.token_hex(6) + ".local"
    probe_user = "probe_user_" + secrets.token_hex(6)
    probe = run([
        'python3', script_path, '--url', probe_url, '--user', probe_user,
        '--pass', probe_password
    ])
    assert probe.returncode == 0, f"Updated deployment script failed: {probe.stderr}"

    prescribed = run([
        'python3', script_path, '--url', 'https://test.local', '--user',
        'security_admin', '--pass', 'NewSecurePass2024!'
    ])
    assert prescribed.returncode == 0, f"Prescribed deployment command failed: {prescribed.stderr}"

    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you run the deploy script?"
    with open(log_path, 'r') as f:
        content = f.read()

    assert "NewSecurePass2024!" not in content, \
        "The plaintext password 'NewSecurePass2024!' was found in the deploy.log file. It should be redacted."
    assert probe_password not in content, \
        "A dynamically supplied plaintext password was found in deploy.log."
    assert "***REDACTED***" in content, \
        "The string '***REDACTED***' was not found in deploy.log. The password should be replaced with this exact string."

    lines = content.splitlines()
    assert any(probe_url in line and probe_user in line and "***REDACTED***" in line for line in lines), \
        "The deployment script did not log the probe URL, username, and redacted password together."
    assert any("https://test.local" in line and "security_admin" in line and "***REDACTED***" in line for line in lines), \
        "The prescribed deployment attempt was not logged with its URL, username, and redacted password."


def test_auth_result_success():
    result_path = "/home/user/auth_result.txt"
    if os.path.exists(result_path):
        os.remove(result_path)

    command = run([
        'python3', '/home/user/auth_test.py', '/home/user/new_cert.pem',
        'security_admin', 'NewSecurePass2024!'
    ])
    assert command.returncode == 0, f"Prescribed authentication command failed: {command.stderr}"
    assert os.path.isfile(result_path), f"Result file {result_path} does not exist. Did you run the auth_test.py script?"

    with open(result_path, 'r') as f:
        content = f.read().strip()

    assert "AUTH_FLOW_SUCCESS" in content, \
        f"Expected 'AUTH_FLOW_SUCCESS' in {result_path}, but found: {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
