#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import importlib.util
import json
import os
import random
import secrets
import requests
from urllib.parse import urlparse

FRONTEND_URL = 'http://127.0.0.1:8080'


def test_forensics_report():
    report_path = '/home/user/forensics_report.json'
    assert os.path.isfile(report_path), f"Forensics report missing at {report_path}"

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, "Forensics report is not valid JSON"

    assert report.get('attacker_ip') == '198.51.100.42', f"Incorrect attacker_ip in forensics report. Got: {report.get('attacker_ip')}"
    assert report.get('extracted_key') == 'KEY-8f4a3b2c1d9e8f7a6b5c4d3e2f1a0b9c', f"Incorrect extracted_key in forensics report. Got: {report.get('extracted_key')}"


def test_frontend_remediation_evil_url():
    try:
        r = requests.get(FRONTEND_URL + '/login?next=http://evil.com', allow_redirects=False, timeout=2)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to frontend service: {e}. Is the service running on port 8080?"
    assert r.status_code == 400, f"Expected HTTP 400 for absolute URL, got {r.status_code}"


def test_frontend_remediation_double_slash():
    try:
        r = requests.get(FRONTEND_URL + '/login?next=//evil.com', allow_redirects=False, timeout=2)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to frontend service: {e}. Is the service running on port 8080?"
    assert r.status_code == 400, f"Expected HTTP 400 for double-slash URL, got {r.status_code}"


def test_frontend_remediation_valid_relative():
    try:
        r = requests.get(FRONTEND_URL + '/login?next=/dashboard', allow_redirects=False, timeout=2)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to frontend service: {e}. Is the service running on port 8080?"
    assert r.status_code == 302, f"Expected HTTP 302 for valid relative URL, got {r.status_code}"
    loc = r.headers.get('Location', '')
    parsed = urlparse(loc)
    assert parsed.path == '/dashboard', f"Expected redirect to /dashboard, got {loc}"


def test_frontend_remediation_no_next():
    try:
        r = requests.get(FRONTEND_URL + '/login', allow_redirects=False, timeout=2)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to frontend service: {e}. Is the service running on port 8080?"
    assert r.status_code == 302, f"Expected HTTP 302 for missing next parameter, got {r.status_code}"
    loc = r.headers.get('Location', '')
    parsed = urlparse(loc)
    assert parsed.path == '/home', f"Expected redirect to /home, got {loc}"


def load_frontend_app():
    assert os.path.isfile('/app/frontend.py'), 'Missing /app/frontend.py'
    spec = importlib.util.spec_from_file_location('submitted_frontend', '/app/frontend.py')
    assert spec is not None and spec.loader is not None, 'Could not load /app/frontend.py'
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, 'app'), '/app/frontend.py does not define a Flask app'
    return module.app


def generated_next_values():
    values = []
    for _ in range(6):
        token = secrets.token_hex(12)
        values.extend([
            '/' + token,
            '/' + token + '/subpath',
            'http://' + token + '.invalid/path',
            'https://' + token + '.invalid/path',
            '//' + token + '.invalid/path',
            token,
            'relative/' + token,
            'ftp://' + token + '.invalid/path',
        ])
    random.SystemRandom().shuffle(values)
    return values


def is_valid_next(value):
    return value.startswith('/') and not value.startswith('//')


def assert_next_response(status_code, location, value, source):
    if is_valid_next(value):
        assert status_code == 302, f"{source}: expected 302 for valid relative URL {value!r}, got {status_code}"
        assert location == value, f"{source}: expected redirect to {value!r}, got {location!r}"
    else:
        assert status_code == 400, f"{source}: expected 400 for invalid URL {value!r}, got {status_code}"


def test_general_relative_url_validation_in_submitted_frontend_and_live_service():
    app = load_frontend_app()
    app.config.update(TESTING=True)
    client = app.test_client()

    for value in generated_next_values():
        local_response = client.get('/login', query_string={'next': value}, follow_redirects=False)
        assert_next_response(
            local_response.status_code,
            local_response.headers.get('Location', ''),
            value,
            'submitted /app/frontend.py',
        )

        try:
            live_response = requests.get(
                FRONTEND_URL + '/login',
                params={'next': value},
                allow_redirects=False,
                timeout=2,
            )
        except requests.exceptions.RequestException as e:
            assert False, f"Failed to connect to frontend service during generated test: {e}"
        assert_next_response(
            live_response.status_code,
            live_response.headers.get('Location', ''),
            value,
            'live frontend service',
        )


def test_backend_running_on_8081():
    try:
        r = requests.get('http://127.0.0.1:8081/', timeout=2)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to backend service on port 8081: {e}"
    assert r.status_code == 200, f"Expected backend HTTP 200 on port 8081, got {r.status_code}"
    assert r.content == b'Backend OK', f"Unexpected backend response on port 8081: {r.content!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
