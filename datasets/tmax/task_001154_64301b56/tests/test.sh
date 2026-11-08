#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import pytest


def test_malicious_ips_file():
    filepath = "/home/user/malicious_ips.txt"
    assert os.path.isfile(filepath), f"File {filepath} is missing."

    with open(filepath, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ips = ["198.51.100.7", "203.0.113.42"]
    assert lines == expected_ips, f"Expected IPs {expected_ips}, but got {lines} in {filepath}"


def test_block_rules_file():
    filepath = "/home/user/block_rules.sh"
    assert os.path.isfile(filepath), f"File {filepath} is missing."

    with open(filepath, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "iptables -A INPUT -s 198.51.100.7 -j DROP",
        "iptables -A INPUT -s 203.0.113.42 -j DROP"
    ]

    # Filter out shebang if present
    actual_rules = [line for line in lines if not line.startswith('#')]
    assert actual_rules == expected_lines, f"Expected block rules {expected_lines}, but got {actual_rules} in {filepath}"


@pytest.fixture(scope="module")
def running_app():
    app_path = "/home/user/app.py"
    assert os.path.isfile(app_path), f"File {app_path} is missing."

    process = subprocess.Popen(["python3", app_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(2)
    assert process.poll() is None, "Flask application exited before tests could run"

    yield process

    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request_without_redirect(url, method="GET"):
    opener = urllib.request.build_opener(NoRedirectHandler())
    request = urllib.request.Request(url, method=method)
    try:
        return opener.open(request, timeout=5)
    except urllib.error.HTTPError as error:
        return error


def assert_dashboard_redirect(response, message):
    assert response.status == 302, f"Expected 302 redirect, got {response.status}"
    location = response.headers.get('Location')
    assert location in ['/dashboard', 'http://127.0.0.1:5000/dashboard'], f"{message}, got Location: {location}"


def test_app_csp_header(running_app):
    opener = urllib.request.build_opener(NoRedirectHandler())
    try:
        response = opener.open('http://127.0.0.1:5000/dashboard', timeout=5)
        csp = response.getheader('Content-Security-Policy')
        assert csp == "default-src 'self'", f"Expected CSP header \"default-src 'self'\", got {csp}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to app: {e}")


def test_app_valid_relative_redirect(running_app):
    opener = urllib.request.build_opener(NoRedirectHandler())
    try:
        response = opener.open('http://127.0.0.1:5000/login?next=/settings', timeout=5)
        assert response.status == 302, f"Expected 302 redirect, got {response.status}"
        loc = response.getheader('Location')
        assert loc in ['/settings', 'http://127.0.0.1:5000/settings'], f"Valid relative redirect failed, got Location: {loc}"
    except urllib.error.HTTPError as e:
        if e.code == 302:
            loc = e.headers.get('Location')
            assert loc in ['/settings', 'http://127.0.0.1:5000/settings'], f"Valid relative redirect failed, got Location: {loc}"
        else:
            pytest.fail(f"HTTP Error: {e}")


def test_app_absolute_url_redirect_blocked(running_app):
    opener = urllib.request.build_opener(NoRedirectHandler())
    try:
        response = opener.open('http://127.0.0.1:5000/login?next=http://evil.com', timeout=5)
        pytest.fail("Expected redirect, but got 200 OK")
    except urllib.error.HTTPError as e:
        if e.code == 302:
            loc = e.headers.get('Location')
            assert loc in ['/dashboard', 'http://127.0.0.1:5000/dashboard'], f"Absolute URL redirect not blocked, got Location: {loc}"
        else:
            pytest.fail(f"HTTP Error: {e}")


def test_app_protocol_relative_redirect_blocked(running_app):
    opener = urllib.request.build_opener(NoRedirectHandler())
    try:
        response = opener.open('http://127.0.0.1:5000/login?next=//evil.com', timeout=5)
        pytest.fail("Expected redirect, but got 200 OK")
    except urllib.error.HTTPError as e:
        if e.code == 302:
            loc = e.headers.get('Location')
            assert loc in ['/dashboard', 'http://127.0.0.1:5000/dashboard'], f"Protocol-relative redirect not blocked, got Location: {loc}"
        else:
            pytest.fail(f"HTTP Error: {e}")


def test_generated_redirect_policy(running_app):
    token = secrets.token_hex(12)
    valid_paths = [
        f"/{token}",
        f"/{token}/account/profile",
        f"/reports/{secrets.token_hex(8)}?view=summary",
    ]
    invalid_targets = [
        f"http://{token}.example/steal",
        f"https://{token}.example/drop",
        f"//{token}.example/path",
        token,
        f"{token}/relative-without-leading-slash",
        f"ftp://{token}.example/file",
    ]

    for target in valid_paths:
        query = urllib.parse.urlencode({'next': target})
        response = request_without_redirect(f"http://127.0.0.1:5000/login?{query}")
        assert response.status == 302, f"Expected 302 for valid relative path {target!r}, got {response.status}"
        location = response.headers.get('Location')
        allowed = [target, f"http://127.0.0.1:5000{target}"]
        assert location in allowed, f"Valid relative redirect {target!r} failed, got Location: {location}"

    for target in invalid_targets:
        query = urllib.parse.urlencode({'next': target})
        response = request_without_redirect(f"http://127.0.0.1:5000/login?{query}")
        assert_dashboard_redirect(response, f"Invalid redirect target {target!r} was not blocked")

    response = request_without_redirect("http://127.0.0.1:5000/login")
    assert_dashboard_redirect(response, "Missing next parameter did not default to /dashboard")

    response = request_without_redirect("http://127.0.0.1:5000/login?next=")
    assert_dashboard_redirect(response, "Empty next parameter did not default to /dashboard")


def test_csp_on_all_response_types(running_app):
    token = secrets.token_hex(12)
    urls_and_methods = [
        ("http://127.0.0.1:5000/dashboard", "GET"),
        ("http://127.0.0.1:5000/login", "GET"),
        ("http://127.0.0.1:5000/login?" + urllib.parse.urlencode({'next': f'/{token}'}), "GET"),
        ("http://127.0.0.1:5000/login?" + urllib.parse.urlencode({'next': f'https://{token}.example/x'}), "GET"),
        (f"http://127.0.0.1:5000/not-found-{token}", "GET"),
        ("http://127.0.0.1:5000/login", "POST"),
    ]

    for url, method in urls_and_methods:
        response = request_without_redirect(url, method=method)
        csp = response.headers.get('Content-Security-Policy')
        assert csp == "default-src 'self'", (
            f"Expected CSP header on {method} {url}, got {csp!r} "
            f"for status {response.status}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
