#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import hmac
import hashlib
import secrets
import subprocess
import threading
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import pytest

APP_DIR = "/home/user/app"
CONFIG_FILE = os.path.join(APP_DIR, "config.json")
SERVER_FILE = os.path.join(APP_DIR, "server.py")
SCANNER_FILE = os.path.join(APP_DIR, "scanner.py")
RESULTS_FILE = os.path.join(APP_DIR, "scan_results.json")
SECRET = "r0tated_s3cr3t_999"
EXPECTED_CSP = "default-src 'self'; script-src 'self' 'nonce-random123';"


def b64url(data):
    return base64.urlsafe_b64encode(data).decode().rstrip('=')


def make_token(header_obj, payload_obj, secret=None, signature=None):
    header = b64url(json.dumps(header_obj, separators=(',', ':')).encode())
    payload = b64url(json.dumps(payload_obj, separators=(',', ':')).encode())
    if signature is None:
        if secret is None:
            sig = ''
        else:
            sig = b64url(hmac.new(secret.encode(), (header + '.' + payload).encode(), hashlib.sha256).digest())
    else:
        sig = signature
    return f"{header}.{payload}.{sig}"


def request_api(token):
    req = urllib.request.Request('http://localhost:5000/api/data')
    req.add_header('Authorization', f'Bearer {token}')
    try:
        resp = urllib.request.urlopen(req, timeout=5)
        return resp.status, resp.headers
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


@pytest.fixture(scope="module")
def server_process():
    """Starts the Flask server in the background and ensures it is terminated after tests."""
    proc = subprocess.Popen(["python3", SERVER_FILE], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    ready = False
    for _ in range(20):
        if proc.poll() is not None:
            out, err = proc.communicate()
            pytest.fail(f"Server exited during startup. stdout={out!r}, stderr={err!r}")
        try:
            urllib.request.urlopen("http://localhost:5000/", timeout=1)
            ready = True
            break
        except urllib.error.HTTPError:
            ready = True
            break
        except urllib.error.URLError:
            time.sleep(0.25)
    assert ready, "Flask server did not become ready on localhost:5000."

    yield proc
    stop_process(proc)


def test_config_updated():
    """Verify the config.json has the updated JWT_SECRET."""
    assert os.path.exists(CONFIG_FILE), f"{CONFIG_FILE} is missing."
    with open(CONFIG_FILE, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{CONFIG_FILE} is not valid JSON.")

    assert config.get("JWT_SECRET") == SECRET, "JWT_SECRET was not correctly updated to the new value."


def test_server_alg_none_rejected(server_process):
    """Verify that the server rejects 'alg=none' JWT tokens with a 401 Unauthorized."""
    header = base64.urlsafe_b64encode(json.dumps({"alg": "none", "typ": "JWT"}).encode()).decode().rstrip('=')
    payload = base64.urlsafe_b64encode(json.dumps({"user": "admin"}).encode()).decode().rstrip('=')
    token = f"{header}.{payload}."

    status, _ = request_api(token)
    assert status == 401, f"Expected 401 Unauthorized for alg=none, got {status}."


def test_server_valid_token_and_csp(server_process):
    """Verify that the server accepts valid tokens signed with the new secret and includes the CSP header."""
    header = base64.urlsafe_b64encode(json.dumps({"alg": "HS256", "typ": "JWT"}).encode()).decode().rstrip('=')
    payload = base64.urlsafe_b64encode(json.dumps({"user": "admin"}).encode()).decode().rstrip('=')
    sig = base64.urlsafe_b64encode(
        hmac.new(SECRET.encode(), (header + '.' + payload).encode(), hashlib.sha256).digest()
    ).decode().rstrip('=')
    token = f"{header}.{payload}.{sig}"

    status, headers = request_api(token)
    assert status == 200, f"Server rejected valid token with new secret, got status {status}."
    actual_csp = headers.get('Content-Security-Policy')
    assert actual_csp == EXPECTED_CSP, f"CSP header is missing or incorrect. Expected: {EXPECTED_CSP}, Got: {actual_csp}"


def test_server_randomized_signature_validation(server_process):
    """Exercise fresh tokens so acceptance cannot be implemented as a fixed-token exception."""
    for _ in range(6):
        nonce = secrets.token_hex(18)
        payload = {"user": "admin", "nonce": nonce, "count": secrets.randbelow(1_000_000)}

        none_token = make_token(
            {"typ": "JWT", "nonce": secrets.token_hex(4), "alg": "none"},
            payload,
            signature=b64url(os.urandom(16)),
        )
        status, _ = request_api(none_token)
        assert status == 401, f"A randomized alg=none token was accepted (status {status})."

        valid_token = make_token(
            {"typ": "JWT", "nonce": secrets.token_hex(4), "alg": "HS256"},
            payload,
            secret=SECRET,
        )
        status, headers = request_api(valid_token)
        assert status == 200, f"A freshly generated correctly signed token was rejected (status {status})."
        assert headers.get('Content-Security-Policy') == EXPECTED_CSP, "A successful /api/data response lacked the exact CSP header."

        bad_random_sig = make_token(
            {"alg": "HS256", "typ": "JWT", "nonce": secrets.token_hex(4)},
            payload,
            signature=b64url(os.urandom(32)),
        )
        status, _ = request_api(bad_random_sig)
        assert status == 401, f"A token with a random invalid signature was accepted (status {status})."

        old_secret_token = make_token(
            {"alg": "HS256", "typ": "JWT", "nonce": secrets.token_hex(4)},
            payload,
            secret="old_compromised_secret_123",
        )
        status, _ = request_api(old_secret_token)
        assert status == 401, f"A token signed with the compromised old secret was accepted (status {status})."


class ReusableHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True


def token_kind(auth_header):
    if not auth_header.startswith('Bearer '):
        return 'invalid'
    token = auth_header[len('Bearer '):]
    try:
        header_b64, payload_b64, sig_b64 = token.split('.')
        header = json.loads(base64.urlsafe_b64decode(header_b64 + '=' * (-len(header_b64) % 4)).decode())
    except Exception:
        return 'invalid'
    if header.get('alg') == 'none':
        return 'none'
    expected = b64url(hmac.new(SECRET.encode(), (header_b64 + '.' + payload_b64).encode(), hashlib.sha256).digest())
    if header.get('alg') == 'HS256' and hmac.compare_digest(sig_b64, expected):
        return 'valid'
    return 'invalid'


def run_scanner_against_mock(mode):
    records = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            kind = token_kind(self.headers.get('Authorization', ''))
            records.append((self.command, self.path, kind))

            if mode == 'positive':
                status = 401 if kind == 'none' else (200 if kind == 'valid' else 400)
                include_csp = kind == 'valid'
            else:
                status = 200 if kind == 'none' else (401 if kind == 'valid' else 400)
                include_csp = False

            body = b'{}'
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            if include_csp:
                self.send_header('Content-Security-Policy', EXPECTED_CSP)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass

    httpd = ReusableHTTPServer(('127.0.0.1', 5000), Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        if os.path.exists(RESULTS_FILE):
            os.remove(RESULTS_FILE)
        result = subprocess.run(["python3", SCANNER_FILE], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, f"Scanner script failed against test server. Stderr: {result.stderr}"
        assert os.path.exists(RESULTS_FILE), f"{RESULTS_FILE} was not created by the scanner."
        with open(RESULTS_FILE, 'r') as f:
            results = json.load(f)
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=5)

    assert ('GET', '/api/data', 'none') in records, "scanner.py did not send the required alg=none GET request."
    assert ('GET', '/api/data', 'valid') in records, "scanner.py did not send a correctly signed HS256 GET request."
    assert set(results.keys()) == {"alg_none_rejected", "csp_enforced"}, "scan_results.json does not have exactly the required schema."
    assert type(results["alg_none_rejected"]) is bool
    assert type(results["csp_enforced"]) is bool
    return results


def test_scanner_script(server_process):
    """Verify the scanner executes, tests the live app, and derives findings from actual responses."""
    assert os.path.exists(SCANNER_FILE), f"{SCANNER_FILE} does not exist."
    assert os.path.isfile(SCANNER_FILE), f"{SCANNER_FILE} is not a regular file."

    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)

    result = subprocess.run(["python3", SCANNER_FILE], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Scanner script failed to execute. Stderr: {result.stderr}"
    assert os.path.exists(RESULTS_FILE), f"{RESULTS_FILE} was not created by the scanner."

    with open(RESULTS_FILE, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_FILE} is not valid JSON.")

    assert results.get("alg_none_rejected") is True, "'alg_none_rejected' in scan results should be True."
    assert results.get("csp_enforced") is True, "'csp_enforced' in scan results should be True."
    assert set(results.keys()) == {"alg_none_rejected", "csp_enforced"}, "scan_results.json does not have exactly the required schema."

    stop_process(server_process)
    time.sleep(0.2)

    positive = run_scanner_against_mock('positive')
    assert positive["alg_none_rejected"] is True
    assert positive["csp_enforced"] is True

    negative = run_scanner_against_mock('negative')
    assert negative["alg_none_rejected"] is False, "scanner.py did not derive alg_none_rejected from Request A's status."
    assert negative["csp_enforced"] is False, "scanner.py did not derive csp_enforced from Request B's status and CSP header."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
