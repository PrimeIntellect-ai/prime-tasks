#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop the image's original mock service so the submission can be exercised
# against verifier-controlled instances.
python3 - <<'PY'
import os
import signal
import time

for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    try:
        with open(f'/proc/{entry}/cmdline', 'rb') as f:
            argv = [x.decode(errors='ignore') for x in f.read().split(b'\0') if x]
        cwd = os.readlink(f'/proc/{entry}/cwd')
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        continue
    if argv and cwd == '/home/user/server' and any(arg == 'server.py' or arg.endswith('/server.py') for arg in argv[1:]):
        try:
            os.kill(int(entry), signal.SIGTERM)
        except ProcessLookupError:
            pass

time.sleep(1)
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.server
import json
import os
import secrets
import socket
import ssl
import stat
import subprocess
import sys
import tempfile
import threading
import urllib.parse

import pytest

SCRIPT_PATH = '/home/user/audit_service.py'
REPORT_PATH = '/home/user/audit_report.json'
PAYLOAD = '<script>alert(1)</script>'


class ReusableHTTPServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


class AuditHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.events.append(self.path)
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == '/':
            self.send_response(200)
            self.send_header('Content-Security-Policy', self.server.csp)
            self.end_headers()
            self.wfile.write(b'Welcome to the verifier mock service')
        elif parsed.path == '/submit':
            value = urllib.parse.parse_qs(parsed.query).get('q', [''])[0]
            if value == PAYLOAD:
                self.send_response(200)
                self.send_header('Content-Type', 'text/html')
                self.end_headers()
                self.wfile.write(('Reflected: ' + value).encode())
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b'Missing or invalid payload')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        pass


def unused_random_port():
    for _ in range(200):
        port = 8000 + secrets.randbelow(201)
        with socket.socket() as sock:
            try:
                sock.bind(('127.0.0.1', port))
            except OSError:
                continue
        return port
    raise RuntimeError('Could not select a free audit port')


def run_case(port, unsafe_inline):
    marker = 'verify-' + secrets.token_hex(8)
    with tempfile.TemporaryDirectory() as td:
        key = os.path.join(td, 'key.pem')
        cert = os.path.join(td, 'cert.pem')
        subprocess.run([
            'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
            '-keyout', key, '-out', cert, '-days', '1', '-nodes',
            '-subj', f'/C=US/O=ComplianceCorp/CN=internal-audit-mock-{marker}'
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        server = ReusableHTTPServer(('127.0.0.1', port), AuditHandler)
        server.csp = (
            "default-src 'self'; script-src 'self' 'unsafe-inline'"
            if unsafe_inline else
            "default-src 'self'; style-src 'unsafe-inline'; script-src 'self'"
        )
        server.events = []
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=cert, keyfile=key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        try:
            if os.path.lexists(REPORT_PATH):
                os.unlink(REPORT_PATH)
            result = subprocess.run(
                [sys.executable, SCRIPT_PATH],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
            assert result.returncode == 0, (
                f'audit_service.py exited with {result.returncode}. '
                f'stdout={result.stdout!r} stderr={result.stderr!r}'
            )
            assert os.path.isfile(REPORT_PATH), 'The script did not generate the audit report.'
            with open(REPORT_PATH, 'r') as f:
                data = json.load(f)

            assert data.get('service_port') == port, 'The script did not discover the active HTTPS port.'
            assert isinstance(data.get('cert_subject'), str)
            assert 'ComplianceCorp' in data['cert_subject']
            assert marker in data['cert_subject'], 'The report did not contain the live certificate subject.'
            assert data.get('csp_unsafe_inline') is unsafe_inline
            assert '/' in server.events, 'The script did not fetch the root endpoint.'

            submit_values = []
            for path in server.events:
                parsed = urllib.parse.urlparse(path)
                if parsed.path == '/submit':
                    submit_values.extend(urllib.parse.parse_qs(parsed.query).get('q', []))

            if unsafe_inline:
                assert data.get('exploit_successful') is True
                assert PAYLOAD in submit_values, 'The exact required XSS payload was not submitted.'
            else:
                assert data.get('exploit_successful') is False
                assert not submit_values, 'The exploit was submitted when script-src was safe.'
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


def test_00_execute_audit_script_against_live_services():
    info = os.lstat(SCRIPT_PATH)
    assert stat.S_ISREG(info.st_mode), f'{SCRIPT_PATH} must be a regular Python script.'
    assert info.st_size > 0, f'{SCRIPT_PATH} is empty.'

    # First use a derived port and put unsafe-inline only in style-src. This
    # detects hard-coded discovery and whole-header substring checks.
    run_case(unused_random_port(), False)
    # Leave the required final report for the original assertions below.
    run_case(8443, True)


def test_audit_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The audit report file {REPORT_PATH} is missing."


def test_audit_report_contents():
    try:
        with open(REPORT_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    assert 'service_port' in data, "Key 'service_port' is missing in the audit report."
    assert data['service_port'] == 8443, f"Expected 'service_port' to be 8443, got {data['service_port']}."

    assert 'csp_unsafe_inline' in data, "Key 'csp_unsafe_inline' is missing in the audit report."
    assert data['csp_unsafe_inline'] is True, f"Expected 'csp_unsafe_inline' to be True, got {data['csp_unsafe_inline']}."

    assert 'exploit_successful' in data, "Key 'exploit_successful' is missing in the audit report."
    assert data['exploit_successful'] is True, f"Expected 'exploit_successful' to be True, got {data['exploit_successful']}."

    assert 'cert_subject' in data, "Key 'cert_subject' is missing in the audit report."
    cert_subject = data['cert_subject']
    assert isinstance(cert_subject, str), f"Expected 'cert_subject' to be a string, got {type(cert_subject)}."
    assert "ComplianceCorp" in cert_subject, "The 'cert_subject' does not contain 'ComplianceCorp'."
    assert "internal-audit-mock" in cert_subject, "The 'cert_subject' does not contain 'internal-audit-mock'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
