#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time

import pytest

SERVICE_DIR = "/home/user/service"
TOKEN_FILE = os.path.join(SERVICE_DIR, "token.txt")
WRAPPER_SCRIPT = os.path.join(SERVICE_DIR, "wrapper.py")
SERVER_SCRIPT = os.path.join(SERVICE_DIR, "server.py")
AUTH_BIN = os.path.join(SERVICE_DIR, "auth_bin")
REPORT_FILE = "/home/user/security_report.json"


def test_report_json_and_token():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} does not exist."

    with open(REPORT_FILE, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {REPORT_FILE} is not valid JSON.")

    assert "env_var_discovered" in report, "Report missing 'env_var_discovered'."
    assert report["env_var_discovered"] == "APP_AUTH_SECRET", "Incorrect environment variable discovered."

    assert "new_token" in report, "Report missing 'new_token'."
    new_token = report["new_token"]
    assert re.match(r"^[a-f0-9]{32}$", new_token), "New token must be a 32-character lowercase hex string."

    assert os.path.isfile(TOKEN_FILE), f"Token file {TOKEN_FILE} does not exist."
    with open(TOKEN_FILE, 'r') as f:
        token_content = f.read().strip()

    assert token_content == new_token, "Content of token.txt does not match 'new_token' in report."


def test_wrapper_fix():
    assert os.path.isfile(WRAPPER_SCRIPT), f"Wrapper script {WRAPPER_SCRIPT} does not exist."

    with open(WRAPPER_SCRIPT, 'r') as f:
        content = f.read()

    assert "OLD_TOKEN_123" not in content, "Wrapper script still contains the old hardcoded token."
    assert "token.txt" in content, "Wrapper script does not seem to read from token.txt."
    assert "APP_AUTH_SECRET" in content, "Wrapper script does not use the APP_AUTH_SECRET environment variable."

    # Preserve the original end-to-end authentication assertion.
    result = subprocess.run(['python3', WRAPPER_SCRIPT], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"wrapper.py failed to execute correctly. stderr: {result.stderr}"
    assert result.stdout.strip() == "OK", "wrapper.py did not output 'OK'."

    # Replace auth_bin briefly with an instrumented stand-in. Rotate token.txt to
    # an unpredictable value so this observes both dynamic file reading and the
    # exact argv/environment used to invoke the backend.
    assert os.path.isfile(AUTH_BIN), "auth_bin does not exist."
    original_token = open(TOKEN_FILE, 'rb').read()
    backup_fd, backup_path = tempfile.mkstemp(prefix="auth_bin_backup_")
    os.close(backup_fd)
    shutil.copy2(AUTH_BIN, backup_path)
    log_fd, log_path = tempfile.mkstemp(prefix="auth_spy_", suffix=".json")
    os.close(log_fd)
    os.unlink(log_path)
    probe_token = os.urandom(16).hex()

    spy = f'''#!/usr/bin/python3
import json
import os
import sys
with open({log_path!r}, "w") as f:
    json.dump({{"argv": sys.argv[1:], "secret": os.environ.get("APP_AUTH_SECRET")}}, f)
with open({TOKEN_FILE!r}, "r") as f:
    expected = f.read().strip()
if os.environ.get("APP_AUTH_SECRET") == expected:
    print("AUTH_SUCCESS")
    sys.exit(0)
print("AUTH_FAIL")
sys.exit(1)
'''

    try:
        with open(TOKEN_FILE, 'w') as f:
            f.write(probe_token)
        with open(AUTH_BIN, 'w') as f:
            f.write(spy)
        os.chmod(AUTH_BIN, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                           stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        result = subprocess.run(['python3', WRAPPER_SCRIPT], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"wrapper.py failed with instrumented backend: {result.stderr}"
        assert result.stdout.strip() == "OK", "wrapper.py did not report successful authentication."
        assert os.path.isfile(log_path), "wrapper.py did not execute auth_bin."
        with open(log_path, 'r') as f:
            invocation = json.load(f)
        assert invocation["secret"] == probe_token, \
            "wrapper.py did not read the current token and inject it through APP_AUTH_SECRET."
        assert invocation["argv"] == [], \
            "wrapper.py passed arguments to auth_bin; the credential must be supplied exclusively via the environment."
    finally:
        with open(TOKEN_FILE, 'wb') as f:
            f.write(original_token)
        shutil.copy2(backup_path, AUTH_BIN)
        os.unlink(backup_path)
        if os.path.exists(log_path):
            os.unlink(log_path)


def _listening_ipv4_sockets_for_pid(pid):
    socket_inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            socket_inodes.add(match.group(1))

    listeners = []
    with open('/proc/net/tcp', 'r') as f:
        next(f)
        for line in f:
            fields = line.split()
            if len(fields) < 10 or fields[3] != '0A' or fields[9] not in socket_inodes:
                continue
            address, port_hex = fields[1].split(':')
            listeners.append((address, int(port_hex, 16)))
    return listeners


def test_server_fix():
    assert os.path.isfile(SERVER_SCRIPT), f"Server script {SERVER_SCRIPT} does not exist."

    with open(SERVER_SCRIPT, 'r') as f:
        content = f.read()

    assert "127.0.0.1" in content, "Server script does not bind to 127.0.0.1."
    assert "0.0.0.0" not in content, "Server script still binds to 0.0.0.0."

    csp_pattern = re.compile(r"Content-Security-Policy.*default-src\s+'self'", re.IGNORECASE)
    assert csp_pattern.search(content), "Server script does not properly send the Content-Security-Policy header."

    # Execute the actual server, make an HTTP request, and inspect its listening
    # socket rather than trusting strings in its source.
    proc = subprocess.Popen(
        ['python3', SERVER_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        response = None
        last_error = None
        for _ in range(50):
            if proc.poll() is not None:
                break
            try:
                conn = http.client.HTTPConnection('127.0.0.1', 8080, timeout=1)
                conn.request('GET', '/')
                response = conn.getresponse()
                response.read()
                conn.close()
                break
            except OSError as exc:
                last_error = exc
                time.sleep(0.1)

        if response is None:
            stderr = proc.stderr.read() if proc.poll() is not None else ""
            pytest.fail(f"server.py did not serve HTTP on 127.0.0.1:8080: {last_error}; stderr: {stderr}")

        assert response.getheader('Content-Security-Policy') == "default-src 'self';", \
            "HTTP response did not contain the required Content-Security-Policy header."

        listeners = _listening_ipv4_sockets_for_pid(proc.pid)
        server_listeners = [(addr, port) for addr, port in listeners if port == 8080]
        assert server_listeners, "The executed server has no listening socket on port 8080."
        assert all(addr == '0100007F' for addr, _ in server_listeners), \
            "The executed server is not bound exclusively to IPv4 loopback 127.0.0.1."
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
