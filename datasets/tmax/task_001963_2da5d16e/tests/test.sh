#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import tempfile
import pytest


def test_domains_txt_content():
    domains_file = '/home/user/forensics/domains.txt'
    assert os.path.isfile(domains_file), f"File {domains_file} does not exist."

    with open(domains_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_domains = ['attacker.net', 'badguy.io', 'malicious-phish.com']
    assert lines == expected_domains, f"Content of {domains_file} is incorrect. Expected {expected_domains}, got {lines}."


def test_clean_authorized_keys_content():
    original_keys_file = '/home/user/.ssh/authorized_keys'
    clean_keys_file = '/home/user/forensics/clean_authorized_keys'

    assert os.path.isfile(original_keys_file), f"Original file {original_keys_file} is missing."
    assert os.path.isfile(clean_keys_file), f"Cleaned file {clean_keys_file} does not exist."

    with open(original_keys_file, 'r') as f:
        original_lines = f.readlines()

    expected_line = next((line for line in original_lines if 'analyst@soc.local' in line), None)
    assert expected_line is not None, "Could not find the valid key in the original authorized_keys file."

    with open(clean_keys_file, 'r') as f:
        clean_content = f.read()

    assert clean_content == expected_line, f"Content of {clean_keys_file} is incorrect. It should contain exactly the valid key with no extra blank lines."


def test_test_security_py():
    test_file = '/home/user/app/test_security.py'
    app_file = '/home/user/app/app.py'
    assert os.path.isfile(test_file), f"Test file {test_file} does not exist."

    with open(test_file, 'r') as f:
        content = f.read()

    assert 'unittest' in content, f"{test_file} does not appear to use the unittest framework."
    assert 'Content-Security-Policy' in content, f"{test_file} does not check for the Content-Security-Policy header."
    assert "default-src 'self'; script-src 'self'" in content, f"{test_file} does not check for the exact CSP value."
    assert 'from app import app' in content or 'import app' in content, f"{test_file} does not import the Flask app."

    env = os.environ.copy()
    env['PYTHONPATH'] = '/home/user/app'
    env['PYTHONDONTWRITEBYTECODE'] = '1'

    def run_unit_test():
        for path in ('/home/user/app/__pycache__',):
            if os.path.isdir(path):
                for name in os.listdir(path):
                    if name.startswith('app.') and name.endswith('.pyc'):
                        os.unlink(os.path.join(path, name))
        return subprocess.run(
            ['python3', '-m', 'unittest', test_file],
            capture_output=True,
            text=True,
            env=env
        )

    # Run the unit test against the real application.
    result = run_unit_test()
    assert result.returncode == 0, f"The unit test {test_file} failed when executed:\n{result.stderr}\n{result.stdout}"

    with open(app_file, 'rb') as f:
        original_app = f.read()

    fd, request_log = tempfile.mkstemp(prefix='csp_requests_', dir='/tmp')
    os.close(fd)
    os.unlink(request_log)

    def instrumented_app(csp_value):
        header_code = '' if csp_value is None else (
            "    response.headers['Content-Security-Policy'] = " + repr(csp_value) + "\n"
        )
        return (
            "from flask import Flask, make_response, request\n\n"
            "app = Flask(__name__)\n\n"
            "@app.before_request\n"
            "def record_request():\n"
            f"    with open({request_log!r}, 'a') as log:\n"
            "        log.write(request.method + ' ' + request.path + '\\n')\n\n"
            "@app.route('/login')\n"
            "def login():\n"
            "    response = make_response('Login Page')\n"
            + header_code +
            "    return response\n"
        )

    try:
        # Confirm that the submitted test actually issues GET /login.
        with open(app_file, 'w') as f:
            f.write(instrumented_app("default-src 'self'; script-src 'self'"))
        valid_result = run_unit_test()
        assert valid_result.returncode == 0, (
            f"The submitted test did not pass against a compliant instrumented app:\n"
            f"{valid_result.stderr}\n{valid_result.stdout}"
        )
        requests = []
        if os.path.exists(request_log):
            with open(request_log, 'r') as f:
                requests = [line.strip() for line in f]
        assert 'GET /login' in requests, "The submitted test did not make a GET request to /login."

        # A real header-presence assertion must fail when the header is absent.
        with open(app_file, 'w') as f:
            f.write(instrumented_app(None))
        missing_result = run_unit_test()
        assert missing_result.returncode != 0, (
            "The submitted test passed even though Content-Security-Policy was absent."
        )

        # An exact-value assertion must fail when the header has another value.
        with open(app_file, 'w') as f:
            f.write(instrumented_app("default-src *; script-src *"))
        wrong_result = run_unit_test()
        assert wrong_result.returncode != 0, (
            "The submitted test passed even though Content-Security-Policy had the wrong value."
        )
    finally:
        with open(app_file, 'wb') as f:
            f.write(original_app)
        if os.path.exists(request_log):
            os.unlink(request_log)
        pycache = '/home/user/app/__pycache__'
        if os.path.isdir(pycache):
            for name in os.listdir(pycache):
                if name.startswith('app.') and name.endswith('.pyc'):
                    os.unlink(os.path.join(pycache, name))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
