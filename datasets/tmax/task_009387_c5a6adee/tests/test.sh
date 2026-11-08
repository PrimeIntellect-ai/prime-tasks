#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

REPORT = '/home/user/audit_report.txt'


def read_report_lines():
    with open(REPORT, 'r') as f:
        return f.read().splitlines()


def test_audit_report_exists():
    assert os.path.exists(REPORT), f"Audit report not found at {REPORT}"
    assert os.path.isfile(REPORT), f"{REPORT} is not a regular file"


def test_audit_report_has_exactly_three_lines():
    lines = read_report_lines()
    assert len(lines) == 3, f"Audit report must contain exactly three lines, found {len(lines)}"


def test_audit_report_line1_integrity():
    server_path = '/home/user/app/server.py'
    baseline_path = '/home/user/compliance/baseline.sha256'

    assert os.path.exists(server_path), "Server file missing"
    assert os.path.exists(baseline_path), "Baseline file missing"

    with open(server_path, 'rb') as f:
        current_hash = hashlib.sha256(f.read()).hexdigest()

    with open(baseline_path, 'r') as f:
        baseline_hash = f.read().strip()

    expected_status = "MATCH" if current_hash == baseline_hash else "MISMATCH"
    expected_line = f"Integrity: {expected_status}"
    lines = read_report_lines()

    assert len(lines) >= 1, "Audit report is empty"
    assert lines[0] == expected_line, f"Line 1 of audit report is incorrect. Expected '{expected_line}', got '{lines[0]}'"


def test_audit_report_line2_token():
    expected_token = "SECURE_COMPLIANCE_99812"
    expected_line = f"Token: {expected_token}"
    lines = read_report_lines()

    assert len(lines) >= 2, "Audit report does not have a second line"
    assert lines[1] == expected_line, f"Line 2 of audit report is incorrect. Expected '{expected_line}', got '{lines[1]}'"


def test_audit_report_line3_pubkey():
    pubkey_path = '/home/user/.ssh/compliance_key.pub'
    assert os.path.exists(pubkey_path), f"Public key not found at {pubkey_path}"

    with open(pubkey_path, 'r') as f:
        pubkey_contents = f.read().strip()

    expected_line = f"PubKey: {pubkey_contents}"
    lines = read_report_lines()

    assert len(lines) >= 3, "Audit report does not have a third line"
    assert lines[2] == expected_line, f"Line 3 of audit report is incorrect. Expected '{expected_line}', got '{lines[2]}'"


def test_exploit_script_executes_curl_redirect_and_extracts_dynamic_token():
    exploit_path = '/home/user/exploit.sh'
    assert os.path.exists(exploit_path), f"Exploit script not found at {exploit_path}"
    assert os.path.isfile(exploit_path), f"{exploit_path} is not a regular file"

    with open(exploit_path, 'r', errors='replace') as f:
        script = f.read()
    noncomment_lines = [line for line in script.splitlines() if not line.lstrip().startswith('#')]
    assert any('curl' in line.lower() for line in noncomment_lines), "Exploit script does not invoke curl"

    # Stop the image's normal server and substitute a one-shot challenge server
    # whose token is generated only at verification time.
    subprocess.run(['pkill', '-f', 'python3 /home/user/app/server.py'], check=False)
    time.sleep(0.2)

    token = 'VERIFY_' + secrets.token_hex(20)
    requests = []

    class ChallengeHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urlparse(self.path)
            query = parse_qs(parsed.query)
            requests.append((parsed.path, query))
            target = query.get('url', ['/'])[0]
            self.send_response(302)
            separator = '&' if '?' in target else '?'
            self.send_header('Location', f'{target}{separator}token={token}')
            self.end_headers()

        def log_message(self, fmt, *args):
            pass

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    server = ReusableHTTPServer(('127.0.0.1', 8080), ChallengeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    with open(REPORT, 'rb') as f:
        original_report = f.read()

    try:
        result = subprocess.run(
            ['runuser', '-u', 'user', '--', 'timeout', '15', 'bash', exploit_path],
            cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=20
        )
        assert result.returncode == 0, f"Exploit script failed: {result.stderr}"

        assert requests, "Exploit script did not make a request to the local application"
        assert any(
            path == '/login' and query.get('url') == ['http://127.0.0.1:9090/audit_catcher']
            for path, query in requests
        ), "Exploit did not request /login with the required audit_catcher redirect URL"

        with open(REPORT, 'rb') as f:
            resulting_report = f.read()
        expected_append = f'Token: {token}\n'.encode()
        assert resulting_report == original_report + expected_append, (
            "Exploit did not extract the verification-time token from Location and append it exactly to the report"
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        with open(REPORT, 'wb') as f:
            f.write(original_report)


def test_ssh_config_hardening():
    config_path = '/home/user/.ssh/config'
    assert os.path.exists(config_path), f"SSH config not found at {config_path}"

    with open(config_path, 'r') as f:
        config_content = f.read()

    # Preserve the original assertions.
    assert "Host audit-vault" in config_content, "SSH config missing 'Host audit-vault'"
    assert "Hostname 127.0.0.1" in config_content or "HostName 127.0.0.1" in config_content, "SSH config missing Hostname for audit-vault"
    assert "IdentityFile /home/user/.ssh/compliance_key" in config_content, "SSH config missing correct IdentityFile"
    assert "Ciphers chacha20-poly1305@openssh.com" in config_content, "SSH config missing correct Ciphers restriction"
    assert "MACs hmac-sha2-512-etm@openssh.com" in config_content, "SSH config missing correct MACs restriction"

    # Require the directives to occur in a real audit-vault Host block.
    blocks = []
    current = None
    for raw_line in config_content.splitlines():
        line = raw_line.split('#', 1)[0].strip()
        if not line:
            continue
        parts = line.split(None, 1)
        keyword = parts[0].lower()
        value = parts[1].strip() if len(parts) == 2 else ''
        if keyword == 'host':
            if current is not None:
                blocks.append(current)
            current = {'patterns': value.split(), 'directives': {}}
        elif current is not None:
            current['directives'].setdefault(keyword, []).append(value)
    if current is not None:
        blocks.append(current)

    matching = [b for b in blocks if 'audit-vault' in b['patterns']]
    assert matching, "No real Host audit-vault block found"
    assert any(
        b['directives'].get('hostname') == ['127.0.0.1'] and
        b['directives'].get('identityfile') == ['/home/user/.ssh/compliance_key'] and
        b['directives'].get('ciphers') == ['chacha20-poly1305@openssh.com'] and
        b['directives'].get('macs') == ['hmac-sha2-512-etm@openssh.com']
        for b in matching
    ), "Host audit-vault block does not contain exactly the required hardening directives"

    # Ask OpenSSH to parse the configuration and verify the effective settings.
    parsed = subprocess.run(
        ['ssh', '-G', '-F', config_path, 'audit-vault'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert parsed.returncode == 0, f"OpenSSH rejected the SSH config: {parsed.stderr}"
    effective = {}
    for line in parsed.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            effective.setdefault(parts[0].lower(), []).append(parts[1].strip())

    assert effective.get('hostname') == ['127.0.0.1'], "Effective HostName is incorrect"
    assert '/home/user/.ssh/compliance_key' in effective.get('identityfile', []), "Effective IdentityFile is incorrect"
    assert effective.get('ciphers') == ['chacha20-poly1305@openssh.com'], "Effective Ciphers are not restricted as required"
    assert effective.get('macs') == ['hmac-sha2-512-etm@openssh.com'], "Effective MACs are not restricted as required"


def test_ssh_private_key_exists():
    key_path = '/home/user/.ssh/compliance_key'
    pubkey_path = '/home/user/.ssh/compliance_key.pub'
    assert os.path.exists(key_path), f"Private key not found at {key_path}"

    with open(key_path, 'r') as f:
        key_content = f.read()
    assert "BEGIN OPENSSH PRIVATE KEY" in key_content, "File does not appear to be a valid OpenSSH private key"

    assert os.path.isfile(key_path), "Private key is not a regular file"
    assert os.path.isfile(pubkey_path), "Public key is not a regular file"

    derived = subprocess.run(
        ['ssh-keygen', '-y', '-P', '', '-f', key_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert derived.returncode == 0, f"Private key is invalid or has a passphrase: {derived.stderr}"

    derived_parts = derived.stdout.strip().split()
    with open(pubkey_path, 'r') as f:
        public_parts = f.read().strip().split()

    assert len(derived_parts) >= 2, "Could not derive a public key from the private key"
    assert len(public_parts) >= 2, "Public key file is malformed"
    assert derived_parts[0] == 'ssh-ed25519', "Private key is not Ed25519"
    assert public_parts[0] == 'ssh-ed25519', "Public key is not Ed25519"
    assert derived_parts[:2] == public_parts[:2], "Public and private keys do not form a valid pair"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
