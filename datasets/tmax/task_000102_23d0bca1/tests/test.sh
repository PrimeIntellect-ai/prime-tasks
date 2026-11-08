#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import socket
import ssl
import subprocess


def run_command(args, timeout=5):
    return subprocess.run(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def test_config_updated():
    config_path = '/home/user/config.json'
    assert os.path.isfile(config_path), f"Configuration file {config_path} is missing."

    with open(config_path, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Configuration file {config_path} is no longer valid JSON."

    assert config.get('port') == 8443, f"Expected port in config to be 8443, got {config.get('port')}."


def test_certificates_exist():
    cert_path = '/home/user/cert.pem'
    key_path = '/home/user/key.pem'

    assert os.path.isfile(cert_path), "Certificate file cert.pem was not created."
    assert os.path.getsize(cert_path) > 0, "Certificate file cert.pem is empty."

    assert os.path.isfile(key_path), "Private key file key.pem was not created."
    assert os.path.getsize(key_path) > 0, "Private key file key.pem is empty."


def test_certificate_and_key_are_valid_matching_and_unencrypted():
    cert_path = '/home/user/cert.pem'
    key_path = '/home/user/key.pem'

    cert_check = run_command(['openssl', 'x509', '-in', cert_path, '-noout'])
    assert cert_check.returncode == 0, f"cert.pem is not a valid X.509 certificate: {cert_check.stderr.decode(errors='replace')}"

    key_check = run_command(['openssl', 'pkey', '-in', key_path, '-check', '-noout'])
    assert key_check.returncode == 0, f"key.pem is not a valid unencrypted private key: {key_check.stderr.decode(errors='replace')}"

    with open(key_path, 'rb') as f:
        key_data = f.read()
    assert b'ENCRYPTED PRIVATE KEY' not in key_data and b'Proc-Type: 4,ENCRYPTED' not in key_data, "key.pem must be unencrypted."

    cert_pub = run_command(['openssl', 'x509', '-in', cert_path, '-pubkey', '-noout'])
    key_pub = run_command(['openssl', 'pkey', '-in', key_path, '-pubout'])
    assert cert_pub.returncode == 0 and key_pub.returncode == 0, "Could not extract public keys from the certificate and private key."
    assert cert_pub.stdout == key_pub.stdout, "cert.pem and key.pem do not contain a matching key pair."

    subject = run_command(['openssl', 'x509', '-in', cert_path, '-noout', '-subject', '-nameopt', 'RFC2253'])
    issuer = run_command(['openssl', 'x509', '-in', cert_path, '-noout', '-issuer', '-nameopt', 'RFC2253'])
    assert subject.returncode == 0 and issuer.returncode == 0, "Could not inspect the certificate subject and issuer."
    assert subject.stdout.partition(b'=')[2].strip() == issuer.stdout.partition(b'=')[2].strip(), "cert.pem is not self-issued."

    self_verify = run_command(['openssl', 'verify', '-check_ss_sig', '-CAfile', cert_path, cert_path])
    assert self_verify.returncode == 0, f"cert.pem is not a valid self-signed certificate: {self_verify.stderr.decode(errors='replace')}"


def test_health_check_output():
    health_path = '/home/user/health_check.txt'
    assert os.path.isfile(health_path), f"Health check output file {health_path} was not created."

    with open(health_path, 'r') as f:
        content = f.read().strip()

    assert content == '{"status": "ok"}', f"Expected health check output to be '{{\"status\": \"ok\"}}', got '{content}'."


def test_server_listening():
    # Keep the original TCP-listening assertion.
    is_listening = False
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1.0)
        result = s.connect_ex(('127.0.0.1', 8443))
        if result == 0:
            is_listening = True

    assert is_listening, "No service is listening on 127.0.0.1:8443. The server might not be running or failed to start."


def test_required_server_process_is_running():
    found = False
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                args = [arg.decode(errors='replace') for arg in f.read().split(b'\0') if arg]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if args and 'python' in os.path.basename(args[0]).lower() and '/home/user/server.py' in args[1:]:
            found = True
            break
    assert found, "python3 /home/user/server.py is not running."


def test_live_https_service_uses_generated_certificate_and_matches_saved_health_output():
    cert_path = '/home/user/cert.pem'
    expected_der = run_command(['openssl', 'x509', '-in', cert_path, '-outform', 'DER'])
    assert expected_der.returncode == 0, "Could not convert cert.pem to DER for comparison."

    context = ssl._create_unverified_context()
    with socket.create_connection(('127.0.0.1', 8443), timeout=3) as raw_socket:
        with context.wrap_socket(raw_socket, server_hostname='localhost') as tls_socket:
            presented_der = tls_socket.getpeercert(binary_form=True)
    assert presented_der == expected_der.stdout, "The TLS service on port 8443 is not using /home/user/cert.pem."

    curl = run_command([
        'curl', '--noproxy', '*', '-k', '-sS', '--fail', '--max-time', '5',
        'https://localhost:8443/health'
    ], timeout=7)
    assert curl.returncode == 0, f"A real HTTPS request to /health failed: {curl.stderr.decode(errors='replace')}"

    live_content = curl.stdout.decode('utf-8').strip()
    assert live_content == '{"status": "ok"}', f"Live health endpoint returned unexpected content: '{live_content}'."

    with open('/home/user/health_check.txt', 'r') as f:
        saved_content = f.read().strip()
    assert saved_content == live_content, "health_check.txt does not exactly match the live HTTPS health endpoint response."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
