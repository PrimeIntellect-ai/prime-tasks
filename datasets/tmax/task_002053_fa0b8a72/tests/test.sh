#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import http.server
import json
import os
import secrets
import shutil
import signal
import subprocess
import threading
import time
from pathlib import Path

import pytest

DECRYPTED = Path('/home/user/decrypted_logs.txt')
PROOF = Path('/home/user/vulnerability_proof.txt')
REPORT = Path('/home/user/compliance_report.json')
ENCRYPTED = Path('/home/user/legacy_logs.enc')
KEY = 'C0mpl1@nc3_K3y_2024'
ENDPOINT = '/admin_backdoor_v99_debug'


def test_decrypted_logs():
    """Verify that the encrypted logs were correctly decrypted."""
    assert DECRYPTED.exists(), f'File not found: {DECRYPTED}'

    expected_plaintext = (
        '[INFO] 2024-01-01 Service started\n'
        '[WARN] 2024-01-02 Low memory\n'
        '[INFO] 2024-01-03 Audit log initialized\n'
        '[ERROR] 2024-01-04 Failed login attempt\n'
    )

    with DECRYPTED.open('r', encoding='utf-8') as f:
        actual_plaintext = f.read()

    assert actual_plaintext == expected_plaintext, (
        f'Contents of {DECRYPTED} do not match the expected decrypted plaintext. '
        'Ensure the XOR decryption and Base64 decoding were applied correctly.'
    )


def test_vulnerability_proof():
    """Verify that the hidden endpoint was successfully accessed."""
    assert PROOF.exists(), f'File not found: {PROOF}'
    expected_proof = 'VULNERABILITY_CONFIRMED_SYSTEM_COMPROMISED'

    with PROOF.open('r', encoding='utf-8') as f:
        actual_proof = f.read()

    assert actual_proof.strip() == expected_proof, (
        f'Contents of {PROOF} do not match the expected vulnerability proof. '
        f"Expected '{expected_proof}', but got '{actual_proof.strip()}'."
    )
    assert actual_proof == expected_proof, 'The proof must be the exact HTTP response body'


def test_compliance_report():
    """Verify the final compliance report JSON structure and values."""
    assert REPORT.exists(), f'File not found: {REPORT}'

    try:
        with REPORT.open('r', encoding='utf-8') as f:
            report_data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f'Failed to parse {REPORT} as valid JSON: {e}')

    assert isinstance(report_data, dict), 'The compliance report must be a JSON object'
    assert set(report_data) == {'encryption_key', 'hidden_endpoint', 'decrypted_lines'}, (
        'The compliance report must contain exactly the three required keys'
    )

    assert 'encryption_key' in report_data, f"Missing 'encryption_key' in {REPORT}"
    assert report_data['encryption_key'] == KEY, (
        f"Incorrect 'encryption_key'. Expected '{KEY}', got '{report_data['encryption_key']}'"
    )

    assert 'hidden_endpoint' in report_data, f"Missing 'hidden_endpoint' in {REPORT}"
    assert report_data['hidden_endpoint'] == ENDPOINT, (
        f"Incorrect 'hidden_endpoint'. Expected '{ENDPOINT}', got '{report_data['hidden_endpoint']}'"
    )

    assert 'decrypted_lines' in report_data, f"Missing 'decrypted_lines' in {REPORT}"
    assert isinstance(report_data['decrypted_lines'], int), "'decrypted_lines' must be an integer"
    assert report_data['decrypted_lines'] == 4, (
        f"Incorrect 'decrypted_lines'. Expected 4, got {report_data['decrypted_lines']}"
    )


def _stop_original_server():
    target = '/home/user/audit_server'
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if os.readlink(entry / 'exe') == target:
                os.kill(int(entry.name), signal.SIGTERM)
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            pass
    time.sleep(0.3)


def _candidate_scripts():
    excluded = {
        Path('/home/user/audit_server'), ENCRYPTED, DECRYPTED, PROOF, REPORT
    }
    supported = {'.py', '.sh', '.bash', '.pl', '.rb', '.js', '.php'}
    candidates = []
    for path in Path('/home/user').rglob('*'):
        try:
            if not path.is_file() or path in excluded:
                continue
            if path.suffix.lower() in supported or os.access(path, os.X_OK):
                candidates.append(path)
        except OSError:
            continue
    return sorted(candidates)


def _base_command(path):
    interpreters = {
        '.py': 'python3', '.sh': 'bash', '.bash': 'bash', '.pl': 'perl',
        '.rb': 'ruby', '.js': 'node', '.php': 'php'
    }
    interpreter = interpreters.get(path.suffix.lower())
    if interpreter:
        executable = shutil.which(interpreter)
        return [executable, str(path)] if executable else None
    if os.access(path, os.X_OK):
        return [str(path)]
    return None


def test_scripts_execute_against_fresh_inputs_and_live_endpoint():
    candidates = _candidate_scripts()
    assert candidates, 'No decryption or vulnerability-scanning script was found'

    token = secrets.token_hex(16)
    expected_plaintext = (
        f'[INFO] dynamic-{token}-alpha\n'
        f'[WARN] dynamic-{token}-beta\n'
        f'[ERROR] dynamic-{token}-gamma\n'
    ).encode('utf-8')
    key_bytes = KEY.encode('utf-8')
    ciphertext = bytes(b ^ key_bytes[i % len(key_bytes)] for i, b in enumerate(expected_plaintext))
    ENCRYPTED.write_bytes(base64.b64encode(ciphertext))

    response_body = ('LIVE_ENDPOINT_' + secrets.token_hex(24)).encode('ascii')
    observed_requests = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            observed_requests.append((self.command, self.path))
            if self.path == ENDPOINT:
                body = response_body
                self.send_response(200)
            else:
                body = b'NOT_THE_HIDDEN_ENDPOINT'
                self.send_response(404)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass

    _stop_original_server()
    server = None
    for _ in range(20):
        try:
            server = http.server.HTTPServer(('127.0.0.1', 8080), Handler)
            break
        except OSError:
            time.sleep(0.1)
    assert server is not None, 'Could not start the verification HTTP service on port 8080'

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    DECRYPTED.unlink(missing_ok=True)
    PROOF.unlink(missing_ok=True)

    decrypt_succeeded = False
    scan_succeeded = False
    url = 'http://127.0.0.1:8080' + ENDPOINT

    try:
        for path in candidates:
            base = _base_command(path)
            if not base:
                continue
            argument_sets = [
                [],
                [str(ENCRYPTED), str(DECRYPTED)],
                [str(ENCRYPTED), str(DECRYPTED), KEY],
                [url, str(PROOF)],
                [ENDPOINT, str(PROOF)],
            ]
            for arguments in argument_sets:
                try:
                    result = subprocess.run(
                        ['runuser', '-u', 'user', '--'] + base + arguments,
                        cwd=str(path.parent), stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, timeout=5, check=False
                    )
                except (subprocess.TimeoutExpired, OSError):
                    continue

                try:
                    if DECRYPTED.exists() and DECRYPTED.read_bytes() == expected_plaintext:
                        decrypt_succeeded = True
                except OSError:
                    pass
                try:
                    if PROOF.exists() and PROOF.read_bytes() == response_body:
                        scan_succeeded = True
                except OSError:
                    pass

                if result.stdout == expected_plaintext:
                    decrypt_succeeded = True
                if result.stdout == response_body:
                    scan_succeeded = True

                if decrypt_succeeded and scan_succeeded:
                    break
            if decrypt_succeeded and scan_succeeded:
                break
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert decrypt_succeeded, (
        'No submitted script successfully decrypted a fresh repeating-key-XOR/Base64 input'
    )
    assert scan_succeeded, (
        'No submitted script captured the fresh response body from the live HTTP service'
    )
    assert ('GET', ENDPOINT) in observed_requests, (
        'The scanning script did not send a GET request to the hidden endpoint'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
