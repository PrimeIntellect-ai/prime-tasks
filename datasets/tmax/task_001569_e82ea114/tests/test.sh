#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import socket
import subprocess
import threading
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

REPORT_PATH = '/home/user/monitor/report.txt'
ENDPOINTS_PATH = '/home/user/monitor/endpoints.json'
MONITOR_PATH = '/home/user/monitor/uptime_monitor.py'


def read_report_exact():
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} is missing."
    with open(REPORT_PATH, 'r') as f:
        return f.read().splitlines()


def run_monitor():
    assert os.path.isfile(MONITOR_PATH), f"{MONITOR_PATH} is missing."
    result = subprocess.run(
        ['python3', MONITOR_PATH],
        cwd='/home/user/monitor',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"uptime_monitor.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), "uptime_monitor.py did not generate report.txt."


def fetch_status(url):
    try:
        response = urllib.request.urlopen(url, timeout=3)
        return response.getcode()
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception:
        return 0


@pytest.fixture(scope='session', autouse=True)
def execute_and_exercise_monitor():
    assert os.path.isfile(ENDPOINTS_PATH), f"{ENDPOINTS_PATH} is missing."
    with open(ENDPOINTS_PATH, 'rb') as f:
        original_config = f.read()

    statuses = [200, 301, 500, 404]
    random.shuffle(statuses)
    routes = {'/' + uuid.uuid4().hex: status for status in statuses}

    class ChallengeHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            status = routes.get(self.path, 404)
            self.send_response(status)
            self.end_headers()

        def log_message(self, *args):
            pass

    challenge_server = ThreadingHTTPServer(('127.0.0.1', 0), ChallengeHandler)
    challenge_thread = threading.Thread(target=challenge_server.serve_forever, daemon=True)
    challenge_thread.start()
    port = challenge_server.server_address[1]

    challenge_sites = [f"http://localhost:{port}{path}" for path in routes]
    challenge_expected = [
        f"{url} - {'UP' if routes[urllib.request.urlparse(url).path] in (200, 301) else 'DOWN'}"
        for url in challenge_sites
    ]

    try:
        with open(ENDPOINTS_PATH, 'w') as f:
            json.dump({'sites': challenge_sites}, f)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        run_monitor()
        assert read_report_exact() == challenge_expected, (
            "The monitor did not generate the correct report for verifier-supplied endpoints."
        )
    finally:
        challenge_server.shutdown()
        challenge_server.server_close()
        with open(ENDPOINTS_PATH, 'wb') as f:
            f.write(original_config)

    fixed_server = None
    fixed_thread = None
    expected_fixed_statuses = {
        '/good1': 200,
        '/good2': 301,
        '/bad': 500,
    }

    existing_is_correct = all(
        fetch_status(f'http://localhost:8080{path}') == status
        for path, status in expected_fixed_statuses.items()
    )

    if not existing_is_correct:
        class FixedHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(expected_fixed_statuses.get(self.path, 404))
                self.end_headers()

            def log_message(self, *args):
                pass

        try:
            fixed_server = ThreadingHTTPServer(('127.0.0.1', 8080), FixedHandler)
        except OSError as exc:
            pytest.fail(f"Port 8080 is occupied by an unexpected service: {exc}")
        fixed_thread = threading.Thread(target=fixed_server.serve_forever, daemon=True)
        fixed_thread.start()

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    run_monitor()

    try:
        yield
    finally:
        if fixed_server is not None:
            fixed_server.shutdown()
            fixed_server.server_close()


def test_endpoints_json_is_valid():
    assert os.path.isfile(ENDPOINTS_PATH), f"{ENDPOINTS_PATH} is missing."
    try:
        with open(ENDPOINTS_PATH, 'r') as f:
            data = json.load(f)
        assert "sites" in data, "endpoints.json must contain a 'sites' key."
        assert isinstance(data["sites"], list), "'sites' in endpoints.json must be a list."
    except json.JSONDecodeError as e:
        pytest.fail(f"endpoints.json is not valid JSON. Did you remove the trailing comma? Error: {e}")


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} was not generated. Did you run the script?"


def test_report_matches_current_sites():
    with open(ENDPOINTS_PATH, 'r') as f:
        data = json.load(f)
    sites = data['sites']
    assert all(isinstance(url, str) for url in sites), "Every entry in 'sites' must be a URL string."
    expected = [
        f"{url} - {'UP' if fetch_status(url) in (200, 301) else 'DOWN'}"
        for url in sites
    ]
    assert read_report_exact() == expected, "report.txt does not correspond to the current sites list."


def test_report_content():
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} is missing."

    expected_lines = [
        "http://localhost:8080/good1 - UP",
        "http://localhost:8080/good2 - UP",
        "http://localhost:8080/bad - DOWN"
    ]

    with open(REPORT_PATH, 'r') as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in report, but found {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
