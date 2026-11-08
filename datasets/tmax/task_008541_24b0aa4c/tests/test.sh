#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from http.cookies import SimpleCookie

import pytest

REPORT_PATH = '/home/user/workspace/compliance_report.json'
APP_PATH = '/home/user/workspace/auth_service/app.py'
ACCESS_LOG_PATH = '/home/user/workspace/logs/access.log'
AUTH_JSON_PATH = '/home/user/workspace/logs/auth.json'

EXPECTED_APP = '''from flask import Flask, request, jsonify, make_response
import logging

app = Flask(__name__)
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

@app.route('/login', methods=['POST'])
def login():
    data = request.json
    if not data:
        return jsonify({"error": "Bad request"}), 400

    if data.get('username') == 'auditor' and data.get('password') == 'compliance_password':
        resp = make_response(jsonify({"status": "success", "audit_receipt": "AUDIT-7734-TX99"}))
        # Vulnerability: Missing Secure flag
        resp.set_cookie('session_token', 'token_val_99283', httponly=True, secure=False)
        return resp
    else:
        return jsonify({"status": "failed"}), 401

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
'''

EXPECTED_ACCESS_LOG = '''10.0.0.5 - - [10/Oct/2023:13:55:36 +0000] "POST /login HTTP/1.1" 401 120 "-" "curl/7.68.0"
192.168.1.55 - - [10/Oct/2023:14:02:10 +0000] "POST /login HTTP/1.1" 401 120 "-" "python-requests"
192.168.1.55 - - [10/Oct/2023:14:02:25 +0000] "POST /login HTTP/1.1" 401 120 "-" "python-requests"
192.168.1.55 - - [10/Oct/2023:14:02:40 +0000] "POST /login HTTP/1.1" 401 120 "-" "python-requests"
192.168.1.55 - - [10/Oct/2023:14:02:55 +0000] "POST /login HTTP/1.1" 401 120 "-" "python-requests"
192.168.1.100 - - [10/Oct/2023:14:05:00 +0000] "POST /login HTTP/1.1" 401 120 "-" "Mozilla/5.0"
'''

EXPECTED_AUTH_JSON = '''{"timestamp": "2023-10-10T13:55:36Z", "ip": "10.0.0.5", "username": "admin", "status": "failed"}
{"timestamp": "2023-10-10T14:02:10Z", "ip": "192.168.1.55", "username": "root", "status": "failed"}
{"timestamp": "2023-10-10T14:02:25Z", "ip": "192.168.1.55", "username": "admin", "status": "failed"}
{"timestamp": "2023-10-10T14:02:40Z", "ip": "192.168.1.55", "username": "user", "status": "failed"}
{"timestamp": "2023-10-10T14:02:55Z", "ip": "192.168.1.55", "username": "test", "status": "failed"}
{"timestamp": "2023-10-10T14:05:00Z", "ip": "192.168.1.100", "username": "auditor", "status": "failed"}
'''


def assert_fixture_integrity():
    expected = {
        APP_PATH: EXPECTED_APP,
        ACCESS_LOG_PATH: EXPECTED_ACCESS_LOG,
        AUTH_JSON_PATH: EXPECTED_AUTH_JSON,
    }
    for path, content in expected.items():
        assert os.path.isfile(path), f'Required fixture is missing or not a regular file: {path}'
        with open(path, 'rb') as f:
            actual = f.read()
        assert actual == content.encode('utf-8'), f'Required fixture was modified: {path}'


def get_expected_brute_force_ip():
    access_failures = []
    with open(ACCESS_LOG_PATH, 'r') as f:
        for line in f:
            match = re.match(r'^(\S+).*?\[(.*?)\].*?"[^"]+"\s+401\s+', line)
            if match:
                ip = match.group(1)
                dt = datetime.strptime(match.group(2), '%d/%b/%Y:%H:%M:%S %z')
                access_failures.append((ip, dt))

    auth_failures = []
    with open(AUTH_JSON_PATH, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            if data.get('status') == 'failed':
                from datetime import timezone
                dt = datetime.strptime(data.get('timestamp'), '%Y-%m-%dT%H:%M:%SZ')
                dt = dt.replace(tzinfo=timezone.utc)
                auth_failures.append((data.get('ip'), dt))

    correlated = []
    for a_ip, a_dt in access_failures:
        for au_ip, au_dt in auth_failures:
            if a_ip == au_ip and a_dt == au_dt:
                correlated.append((a_ip, a_dt))
                break

    ip_times = {}
    for ip, dt in correlated:
        ip_times.setdefault(ip, []).append(dt)

    for ip, times in ip_times.items():
        times.sort()
        for i in range(len(times)):
            count = 1
            for j in range(i + 1, len(times)):
                if (times[j] - times[i]).total_seconds() <= 60:
                    count += 1
            if count > 3:
                return ip
    return None


def get_expected_app_config():
    with open(APP_PATH, 'r') as f:
        content = f.read()

    audit_receipt = None
    match_receipt = re.search(r'"audit_receipt":\s*"([^"]+)"', content)
    if match_receipt:
        audit_receipt = match_receipt.group(1)

    secure_flag = bool(re.search(r'secure\s*=\s*True', content, re.IGNORECASE))
    httponly_flag = bool(re.search(r'httponly\s*=\s*True', content, re.IGNORECASE))
    return audit_receipt, secure_flag, httponly_flag


def exercise_login_endpoint():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]

    runner = '''
import importlib.util
import sys
spec = importlib.util.spec_from_file_location("verified_auth_service", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.app.run(host="127.0.0.1", port=int(sys.argv[2]), use_reloader=False)
'''
    proc = subprocess.Popen(
        [sys.executable, '-c', runner, APP_PATH, str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        url = f'http://127.0.0.1:{port}/login'
        payload = json.dumps({
            'username': 'auditor',
            'password': 'compliance_password',
        }).encode('utf-8')
        response = None
        last_error = None
        for _ in range(50):
            if proc.poll() is not None:
                pytest.fail('Authentication service exited before accepting requests.')
            try:
                request = urllib.request.Request(
                    url,
                    data=payload,
                    headers={'Content-Type': 'application/json'},
                    method='POST',
                )
                response = urllib.request.urlopen(request, timeout=1)
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)
        assert response is not None, f'Could not reach authentication endpoint: {last_error}'
        with response:
            assert response.status == 200, f'Expected successful login status 200, got {response.status}'
            body = json.loads(response.read().decode('utf-8'))
            set_cookie_headers = response.headers.get_all('Set-Cookie') or []

        session_cookie = None
        for header in set_cookie_headers:
            parsed = SimpleCookie()
            parsed.load(header)
            if 'session_token' in parsed:
                session_cookie = parsed['session_token']
                break
        assert session_cookie is not None, 'Successful login did not set a session_token cookie.'
        return (
            body.get('audit_receipt'),
            bool(session_cookie['secure']),
            bool(session_cookie['httponly']),
        )
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)


def test_fixture_integrity():
    assert_fixture_integrity()


def test_compliance_report_exists():
    assert os.path.isfile(REPORT_PATH), f'The compliance report is missing at {REPORT_PATH}.'


def test_compliance_report_contents():
    assert_fixture_integrity()
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {REPORT_PATH} does not contain valid JSON.')

    expected_ip = get_expected_brute_force_ip()
    expected_receipt, expected_secure, expected_httponly = get_expected_app_config()

    assert 'brute_force_ip' in report, "Missing 'brute_force_ip' in compliance report."
    assert report['brute_force_ip'] == expected_ip, f"Expected brute_force_ip to be {expected_ip}, got {report['brute_force_ip']}."

    assert 'cookie_secure_flag' in report, "Missing 'cookie_secure_flag' in compliance report."
    assert report['cookie_secure_flag'] is expected_secure, f"Expected cookie_secure_flag to be {expected_secure}, got {report['cookie_secure_flag']}."

    assert 'cookie_httponly_flag' in report, "Missing 'cookie_httponly_flag' in compliance report."
    assert report['cookie_httponly_flag'] is expected_httponly, f"Expected cookie_httponly_flag to be {expected_httponly}, got {report['cookie_httponly_flag']}."

    assert 'audit_receipt' in report, "Missing 'audit_receipt' in compliance report."
    assert report['audit_receipt'] == expected_receipt, f"Expected audit_receipt to be {expected_receipt}, got {report['audit_receipt']}."

    live_receipt, live_secure, live_httponly = exercise_login_endpoint()
    assert live_receipt == expected_receipt, 'The running endpoint returned an unexpected audit receipt.'
    assert live_secure is expected_secure, 'The source-derived Secure setting disagrees with the response cookie.'
    assert live_httponly is expected_httponly, 'The source-derived HttpOnly setting disagrees with the response cookie.'
    assert report['audit_receipt'] == live_receipt, 'Report audit_receipt does not match the live endpoint.'
    assert report['cookie_secure_flag'] is live_secure, 'Report Secure flag does not match the live response cookie.'
    assert report['cookie_httponly_flag'] is live_httponly, 'Report HttpOnly flag does not match the live response cookie.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
