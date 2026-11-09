#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

EXPECTED_RESTORE = b'''#!/usr/bin/env python3
import os
import subprocess
import sys

# Simulating restore operation
log_dir = os.path.join(os.environ.get('HOME', '/tmp'), 'logs')
log_file = os.path.join(log_dir, 'restore.log')
fallback_log = '/tmp/fallback.log'

try:
    if not os.path.exists(log_dir):
        os.makedirs(log_dir, exist_ok=True)

    # Relies on standard PATH to find tar
    result = subprocess.run(['tar', '--version'], capture_output=True, text=True)
    if result.returncode == 0:
        with open(log_file, 'w') as f:
            f.write("RESTORE JOB: SUCCESS\\n")
        print("Restore logged successfully.")
    else:
        raise Exception("tar command failed")
except Exception as e:
    with open(fallback_log, 'w') as f:
        f.write(f"RESTORE JOB: FAILED - {str(e)}\\n")
    print("Restore failed, writing to fallback.")
    sys.exit(1)
'''


def test_wrapper_fix():
    wrapper_path = '/home/user/run_wrapper.sh'
    restore_path = '/home/user/restore.py'
    log_file = '/home/user/logs/restore.log'
    fallback_log = '/tmp/fallback.log'

    assert os.path.isfile(wrapper_path), f"Wrapper script {wrapper_path} does not exist."
    assert os.path.isfile(restore_path), f"Restore script {restore_path} does not exist."

    with open(restore_path, 'rb') as f:
        original = f.read()
    assert original == EXPECTED_RESTORE, "restore.py was modified."

    original_mode = stat.S_IMODE(os.stat(restore_path).st_mode)
    probe_output = f"/tmp/wrapper_env_{secrets.token_hex(16)}.json"
    probe = (
        "import json, os\n"
        f"with open({probe_output!r}, 'w') as f:\n"
        "    json.dump(dict(os.environ), f)\n"
    ).encode()

    try:
        with open(restore_path, 'wb') as f:
            f.write(probe)
        os.chmod(restore_path, original_mode)
        probe_result = subprocess.run(
            ['bash', wrapper_path], capture_output=True, text=True, timeout=10
        )
        assert probe_result.returncode == 0, (
            f"Wrapper failed while invoking restore.py. Stdout: {probe_result.stdout}, "
            f"Stderr: {probe_result.stderr}"
        )
        assert os.path.isfile(probe_output), "Wrapper did not execute /home/user/restore.py."
        with open(probe_output) as f:
            wrapper_env = json.load(f)
        assert wrapper_env.get('HOME') == '/home/user', (
            f"Expected HOME=/home/user under env -i, got {wrapper_env.get('HOME')!r}"
        )
        path_parts = wrapper_env.get('PATH', '').split(':')
        assert '/bin' in path_parts and '/usr/bin' in path_parts, (
            f"PATH supplied by wrapper must include /bin and /usr/bin; got {wrapper_env.get('PATH')!r}"
        )
    finally:
        with open(restore_path, 'wb') as f:
            f.write(original)
        os.chmod(restore_path, original_mode)
        if os.path.exists(probe_output):
            os.remove(probe_output)

    if os.path.exists(log_file):
        os.remove(log_file)
    if os.path.exists(fallback_log):
        os.remove(fallback_log)

    result = subprocess.run(
        ['bash', wrapper_path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Wrapper failed. Stdout: {result.stdout}, Stderr: {result.stderr}"
    )
    assert os.path.isfile(log_file), (
        f"Wrapper script failed to create {log_file}. "
        f"Stdout: {result.stdout}, Stderr: {result.stderr}"
    )
    with open(log_file) as f:
        content = f.read()
    assert 'SUCCESS' in content, (
        f"Log file {log_file} does not contain 'SUCCESS'. Actual content: {content}"
    )
    assert not os.path.exists(fallback_log), "restore.py wrote its failure fallback log."


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


class DummyBackendHandler(BaseHTTPRequestHandler):
    responses = {'/api/status': (201, b'BACKEND_DATA')}
    requests = []
    lock = threading.Lock()

    def do_GET(self):
        with self.lock:
            self.requests.append(self.path)
            response = self.responses.get(self.path)
        if response is None:
            response = (404, b'UNKNOWN_PATH')
        status, body = response
        self.send_response(status)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


@pytest.fixture(scope='module')
def backend_server():
    DummyBackendHandler.requests = []
    server = ReusableHTTPServer(('127.0.0.1', 8080), DummyBackendHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield server
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)


@pytest.fixture(scope='module')
def proxy_server():
    proxy_path = '/home/user/health_proxy.py'
    assert os.path.isfile(proxy_path), f"Proxy script {proxy_path} does not exist."
    proc = subprocess.Popen(
        ['python3', proxy_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    time.sleep(2)
    if proc.poll() is not None:
        stdout, stderr = proc.communicate()
        pytest.fail(
            f"Proxy server crashed on startup. Stdout: {stdout.decode()}, "
            f"Stderr: {stderr.decode()}"
        )
    yield proc
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def request_result(url):
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def test_health_proxy_success(proxy_server, backend_server):
    log_file = '/home/user/logs/restore.log'
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    with open(log_file, 'w') as f:
        f.write('RESTORE JOB: SUCCESS\n')

    status, body = request_result('http://127.0.0.1:9090/health')
    assert status == 200, f"Expected status 200, got {status}"
    assert body.decode('utf-8').strip() == 'OK', f"Expected body 'OK', got {body!r}"


def test_health_proxy_failure(proxy_server):
    log_file = '/home/user/logs/restore.log'
    backup_log = '/home/user/logs/restore.log.bak'
    if os.path.exists(backup_log):
        os.remove(backup_log)
    if os.path.exists(log_file):
        os.rename(log_file, backup_log)

    try:
        status, body = request_result('http://127.0.0.1:9090/health')
        assert status == 503, f"Expected status 503, got {status}"
        assert body.decode('utf-8').strip() == 'FAIL', f"Expected body 'FAIL', got {body!r}"
    finally:
        if os.path.exists(backup_log):
            os.rename(backup_log, log_file)


def test_health_proxy_failure_content(proxy_server):
    log_file = '/home/user/logs/restore.log'
    with open(log_file, 'w') as f:
        f.write('RESTORE JOB: FAILED\n')
    status, body = request_result('http://127.0.0.1:9090/health')
    assert status == 503, f"Expected status 503, got {status}"
    assert body.decode('utf-8').strip() == 'FAIL', f"Expected body 'FAIL', got {body!r}"


def test_health_proxy_forwarding(proxy_server, backend_server):
    before = len(DummyBackendHandler.requests)
    status, body = request_result('http://127.0.0.1:9090/api/status')
    assert status == 201, f"Expected status 201 from backend, got {status}"
    assert body.decode('utf-8').strip() == 'BACKEND_DATA', (
        f"Expected body 'BACKEND_DATA', got {body!r}"
    )
    assert DummyBackendHandler.requests[before:] == ['/api/status'], (
        "Proxy returned the expected fixed response without forwarding /api/status."
    )


def test_health_proxy_dynamic_forwarding(proxy_server, backend_server):
    token = secrets.token_hex(16)
    cases = [
        (f'/dynamic/{token}/alpha?item={token}', 202, f'alpha-{token}'.encode()),
        (f'/dynamic/{token}/missing?code=418', 418, f'teapot-{token}'.encode()),
        (f'/health?probe={token}', 207, f'not-health-{token}'.encode()),
    ]
    for path, status, body in cases:
        DummyBackendHandler.responses[path] = (status, body)

    before = len(DummyBackendHandler.requests)
    for path, expected_status, expected_body in cases:
        status, body = request_result('http://127.0.0.1:9090' + path)
        assert status == expected_status, (
            f"For {path}, expected backend status {expected_status}, got {status}"
        )
        assert body == expected_body, (
            f"For {path}, expected backend body {expected_body!r}, got {body!r}"
        )

    assert DummyBackendHandler.requests[before:] == [case[0] for case in cases], (
        "Proxy did not forward each exact randomized request path to the backend."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
