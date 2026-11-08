#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any copy of the application left running by the agent so the verifier can
# launch and exercise the submitted artifact itself.
for proc in /proc/[0-9]*; do
    [ -r "$proc/cmdline" ] || continue
    cmdline=$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)
    case "$cmdline" in
        *python*"/home/user/app.py"*) kill "${proc##*/}" 2>/dev/null || true ;;
    esac
done
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import random
import re
import socket
import ssl
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

CERT_PATH = '/home/user/new_cert.pem'
KEY_PATH = '/home/user/new_key.pem'
APP_PATH = '/home/user/app.py'
VERIFY_PATH = '/home/user/verify.sh'
LOG_PATH = '/home/user/audit_log.txt'
TOKEN = 'NEW_ROTATED_TOKEN_2024'
EXPECTED_CSP = "default-src 'self';"


def openssl(*args, input_data=None):
    result = subprocess.run(
        ['openssl', *args], input=input_data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=True
    )
    return result.stdout


def https_request(token=None):
    context = ssl._create_unverified_context()
    conn = http.client.HTTPSConnection('127.0.0.1', 8443, context=context, timeout=3)
    headers = {}
    if token is not None:
        headers['Authorization'] = f'Bearer {token}'
    conn.connect()
    peer_cert = conn.sock.getpeercert(binary_form=True)
    conn.request('GET', '/data', headers=headers)
    response = conn.getresponse()
    body = response.read()
    values = (response.status, response.getheader('Content-Security-Policy'), body, peer_cert)
    conn.close()
    return values


def test_new_certificates_exist():
    """Verify that the new certificate and key files exist and are correct."""
    assert os.path.exists(CERT_PATH), f"New certificate not found at {CERT_PATH}."
    assert os.path.exists(KEY_PATH), f"New key not found at {KEY_PATH}."
    assert os.path.isfile(CERT_PATH), f"{CERT_PATH} is not a regular file."
    assert os.path.isfile(KEY_PATH), f"{KEY_PATH} is not a regular file."

    with open(CERT_PATH, 'r') as f:
        cert_content = f.read()
    assert "BEGIN CERTIFICATE" in cert_content, f"{CERT_PATH} does not appear to be a valid PEM certificate."

    with open(KEY_PATH, 'r') as f:
        key_content = f.read()
    assert "PRIVATE KEY" in key_content, f"{KEY_PATH} does not appear to be a valid private key."

    openssl('x509', '-in', CERT_PATH, '-noout')
    key_text = openssl('pkey', '-in', KEY_PATH, '-check', '-text', '-noout').decode(errors='replace')
    assert re.search(r'Private-Key:\s*\(2048 bit', key_text), 'The private key is not an RSA 2048-bit key.'

    subject = openssl('x509', '-in', CERT_PATH, '-noout', '-subject', '-nameopt', 'RFC2253').decode().strip()
    subject_value = re.sub(r'^subject\s*=\s*', '', subject)
    assert re.search(r'(^|,)CN=localhost(,|$)', subject_value), f'Certificate CN is not localhost: {subject}'

    issuer = openssl('x509', '-in', CERT_PATH, '-noout', '-issuer', '-nameopt', 'RFC2253').decode().strip()
    issuer_value = re.sub(r'^issuer\s*=\s*', '', issuer)
    assert issuer_value == subject_value, 'Certificate is not self-signed.'
    openssl('verify', '-CAfile', CERT_PATH, CERT_PATH)

    cert_pub_pem = openssl('x509', '-in', CERT_PATH, '-pubkey', '-noout')
    cert_pub_der = openssl('pkey', '-pubin', '-outform', 'DER', input_data=cert_pub_pem)
    key_pub_der = openssl('pkey', '-in', KEY_PATH, '-pubout', '-outform', 'DER')
    assert cert_pub_der == key_pub_der, 'The certificate and private key do not correspond.'


def test_app_py_updated():
    """Verify that app.py has been updated with the required security changes."""
    assert os.path.exists(APP_PATH), f"{APP_PATH} is missing."

    with open(APP_PATH, 'r') as f:
        app_code = f.read()

    assert '127.0.0.1' in app_code, "app.py is not bound to 127.0.0.1."
    assert '0.0.0.0' not in app_code, "app.py is still bound to 0.0.0.0."
    assert 'NEW_ROTATED_TOKEN_2024' in app_code, "app.py does not contain the rotated token NEW_ROTATED_TOKEN_2024."
    assert 'new_cert.pem' in app_code, "app.py does not reference new_cert.pem."
    assert 'new_key.pem' in app_code, "app.py does not reference new_key.pem."
    assert 'Content-Security-Policy' in app_code, "app.py does not contain Content-Security-Policy."


def test_verify_script_exists_and_targets_service():
    assert os.path.isfile(VERIFY_PATH), f'Verification script missing at {VERIFY_PATH}.'
    with open(VERIFY_PATH, 'r') as f:
        script = f.read()
    assert 'curl' in script, 'verify.sh does not use curl.'
    assert 'https://127.0.0.1:8443/data' in script, 'verify.sh does not request the required URL.'
    assert TOKEN in script and 'Authorization' in script, 'verify.sh does not send the rotated Authorization token.'
    assert '/home/user/audit_log.txt' in script, 'verify.sh does not write the required audit log.'


def test_live_application_and_execute_verify_script():
    proc = subprocess.Popen(
        ['python3', APP_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    )
    try:
        last_error = None
        for _ in range(40):
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode(errors='replace')
                raise AssertionError(f'app.py exited before serving requests: {stderr}')
            try:
                status, csp, body, peer_der = https_request(TOKEN)
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.25)
        else:
            raise AssertionError(f'app.py did not start an HTTPS service: {last_error}')

        assert status == 200, f'New token returned HTTP {status}, not 200.'
        assert csp == EXPECTED_CSP, f'Incorrect CSP response header: {csp!r}'
        assert json.loads(body) == {'data': 'secure sensitive data'}, f'Unexpected successful response body: {body!r}'

        cert_der = openssl('x509', '-in', CERT_PATH, '-outform', 'DER')
        assert peer_der == cert_der, 'The running service is not presenting new_cert.pem.'

        old_status, _, _, _ = https_request('OLD_SUPER_SECRET')
        missing_status, _, _, _ = https_request(None)
        assert old_status == 401, f'The old token was not rejected (HTTP {old_status}).'
        assert missing_status == 401, f'A request without authentication was not rejected (HTTP {missing_status}).'

        listeners = []
        with open('/proc/net/tcp', 'r') as f:
            for line in f.readlines()[1:]:
                fields = line.split()
                local_addr, local_port = fields[1].split(':')
                if int(local_port, 16) == 8443 and fields[3] == '0A':
                    listeners.append(local_addr)
        assert listeners, 'No IPv4 listener was found on port 8443.'
        assert set(listeners) == {'0100007F'}, f'Service is not exclusively bound to 127.0.0.1: {listeners}'
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

    # Exercise verify.sh against a verifier-controlled HTTPS response with
    # randomized JSON whitespace. This proves the script extracts the raw body
    # rather than merely writing a pre-fabricated audit log.
    spaces1 = ' ' * random.randint(3, 20)
    spaces2 = ' ' * random.randint(3, 20)
    challenge_body = ('{"data"' + spaces1 + ':' + spaces2 + '"secure sensitive data"}').encode()
    observed = {'authorized': False, 'path': None}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            observed['path'] = self.path
            observed['authorized'] = self.headers.get('Authorization') == f'Bearer {TOKEN}'
            if self.path != '/data' or not observed['authorized']:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'{"error":"Unauthorized"}')
                return
            self.send_response(200)
            self.send_header('Content-Security-Policy', EXPECTED_CSP)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(challenge_body)))
            self.end_headers()
            self.wfile.write(challenge_body)

        def log_message(self, format, *args):
            pass

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    server = ReusableHTTPServer(('127.0.0.1', 8443), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(CERT_PATH, KEY_PATH)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)
        result = subprocess.run(
            ['/bin/bash', VERIFY_PATH], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=15
        )
        assert result.returncode == 0, f'verify.sh failed: {result.stderr.decode(errors="replace")}'
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert observed['path'] == '/data', f'verify.sh requested the wrong path: {observed["path"]!r}'
    assert observed['authorized'], 'verify.sh did not send the correct Bearer token.'
    assert os.path.isfile(LOG_PATH), f'Audit log missing at {LOG_PATH} after running verify.sh.'
    with open(LOG_PATH, 'r') as f:
        lines = f.read().splitlines()
    assert lines == [
        'Status: 200',
        "CSP: default-src 'self';",
        'Body: ' + challenge_body.decode(),
    ], f'Audit log does not contain the exact values extracted from the HTTPS response: {lines!r}'


def test_audit_log_contents():
    """Verify that the audit log exists and contains the correct values."""
    assert os.path.exists(LOG_PATH), f"Audit log missing at {LOG_PATH}."

    with open(LOG_PATH, 'r') as f:
        log_data = f.read()

    assert re.search(r'Status:\s*200', log_data), "Audit log does not show HTTP Status 200."
    assert re.search(r"CSP:\s*default-src\s+'self';", log_data), "Audit log does not correctly report the CSP header."

    # Check body for expected JSON content, tolerant of spacing
    assert '"data"' in log_data, "Audit log Body missing 'data' key."
    assert '"secure sensitive data"' in log_data, "Audit log Body missing 'secure sensitive data' value."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
