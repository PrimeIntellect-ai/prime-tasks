#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import secrets
import string
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest


def expected_backup_name(service, date):
    value = f"{service}-{date}-BKP-s@ltY88".encode()
    return hashlib.sha256(value).hexdigest()


def test_backup_name_gen_fuzz_equivalence():
    agent_bin = '/home/user/backup_name_gen'
    agent_src = '/home/user/backup_name_gen.go'

    assert os.path.isfile(agent_src), f"{agent_src} does not exist."
    assert os.path.isfile(agent_bin), f"{agent_bin} does not exist."
    assert os.access(agent_bin, os.X_OK), f"{agent_bin} is not executable."

    rebuilt_bin = '/tmp/backup_name_gen_rebuilt'
    build = subprocess.run(
        ['go', 'build', '-o', rebuilt_bin, agent_src],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"backup_name_gen.go did not compile: {build.stderr}"

    random.seed(42)
    cases = []
    for _ in range(100):
        length = random.randint(5, 15)
        arg1 = ''.join(random.choices(string.ascii_letters + string.digits, k=length))
        year = random.randint(1990, 2030)
        month = random.randint(1, 12)
        day = random.randint(1, 28)
        arg2 = f"{year:04d}-{month:02d}-{day:02d}"
        cases.append((arg1, arg2))

    for arg1, arg2 in cases:
        expected = expected_backup_name(arg1, arg2)
        for candidate in (agent_bin, rebuilt_bin):
            proc = subprocess.run([candidate, arg1, arg2], capture_output=True, text=True)
            assert proc.returncode == 0, f"{candidate} failed for ({arg1!r}, {arg2!r})."
            assert proc.stdout == expected, (
                f"Output mismatch for {candidate} with inputs ({arg1!r}, {arg2!r}).\n"
                f"Expected: {expected!r}\nGot: {proc.stdout!r}"
            )


def test_submit_exp():
    script_path = '/home/user/submit.exp'
    tool_path = '/app/submit_backup'
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    proc = subprocess.run([script_path, 'test_service', '2023-01-01'], capture_output=True, text=True)
    assert proc.returncode == 0, "submit.exp failed to execute successfully."
    assert "Done" in proc.stdout, "submit.exp did not complete the interactive prompt successfully."

    service = 'svc_' + secrets.token_hex(8)
    date = f"20{random.randint(10, 39):02d}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"
    log_path = '/tmp/submit_interaction_' + secrets.token_hex(8) + '.json'
    saved_tool = '/tmp/original_submit_backup_' + secrets.token_hex(8)

    os.replace(tool_path, saved_tool)
    try:
        instrumented_tool = f'''#!/usr/bin/env python3
import json
import sys
sys.stdout.write("Enter service: ")
sys.stdout.flush()
svc = sys.stdin.readline().rstrip("\\r\\n")
sys.stdout.write("Enter date: ")
sys.stdout.flush()
date = sys.stdin.readline().rstrip("\\r\\n")
sys.stdout.write("Proceed? [y/N]: ")
sys.stdout.flush()
answer = sys.stdin.readline().rstrip("\\r\\n")
with open({log_path!r}, "w") as f:
    json.dump([svc, date, answer], f)
if answer == "y":
    print("Done")
    raise SystemExit(0)
raise SystemExit(1)
'''
        with open(tool_path, 'w') as f:
            f.write(instrumented_tool)
        os.chmod(tool_path, 0o755)

        proc = subprocess.run([script_path, service, date], capture_output=True, text=True, timeout=10)
        assert proc.returncode == 0, "submit.exp did not successfully automate the instrumented CLI."
        assert "Done" in proc.stdout
        assert os.path.isfile(log_path), "submit.exp did not execute /app/submit_backup."
        with open(log_path) as f:
            interaction = json.load(f)
        assert interaction == [service, date, 'y'], (
            f"Incorrect interactive responses: expected {[service, date, 'y']!r}, got {interaction!r}"
        )
    finally:
        try:
            os.unlink(tool_path)
        except FileNotFoundError:
            pass
        os.replace(saved_tool, tool_path)
        if os.path.exists(log_path):
            os.unlink(log_path)


class MockBackendHandler(BaseHTTPRequestHandler):
    requests = []
    dynamic_token = None

    def do_GET(self):
        self.__class__.requests.append(('GET', self.path, b'', self.headers.get('X-Test-Token')))
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"Backend OK")

    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        self.__class__.requests.append(('POST', self.path, body, self.headers.get('X-Test-Token')))
        response = b'forwarded-' + self.__class__.dynamic_token.encode() + b'-' + body
        self.send_response(201)
        self.send_header('Content-type', 'application/octet-stream')
        self.send_header('X-Backend-Token', self.__class__.dynamic_token)
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, format, *args):
        pass


def test_proxy():
    proxy_bin = '/home/user/proxy'
    proxy_src = '/home/user/proxy.go'
    assert os.path.isfile(proxy_src), f"{proxy_src} does not exist."
    assert os.path.isfile(proxy_bin), f"{proxy_bin} does not exist."
    assert os.access(proxy_bin, os.X_OK), f"{proxy_bin} is not executable."

    build = subprocess.run(
        ['go', 'build', '-o', '/tmp/proxy_rebuilt', proxy_src],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"proxy.go did not compile: {build.stderr}"

    token = secrets.token_hex(12)
    body = ('payload-' + secrets.token_hex(16)).encode()
    path = '/api/' + secrets.token_hex(6) + '?q=' + secrets.token_hex(5)
    MockBackendHandler.requests = []
    MockBackendHandler.dynamic_token = token

    server = HTTPServer(('127.0.0.1', 9090), MockBackendHandler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    try:
        time.sleep(0.5)

        req = urllib.request.Request('http://127.0.0.1:8080/')
        with urllib.request.urlopen(req, timeout=3) as response:
            response_body = response.read().decode('utf-8')
            assert response.status == 200
            assert response_body == "Backend OK", "Proxy did not return expected response from backend."

        req = urllib.request.Request(
            'http://127.0.0.1:8080' + path,
            data=body,
            method='POST',
            headers={'X-Test-Token': token, 'Content-Type': 'application/octet-stream'},
        )
        with urllib.request.urlopen(req, timeout=3) as response:
            response_body = response.read()
            assert response.status == 201
            assert response.headers.get('X-Backend-Token') == token
            assert response_body == b'forwarded-' + token.encode() + b'-' + body

        assert ('POST', path, body, token) in MockBackendHandler.requests, (
            "Proxy did not forward the request method, path, query, body, and headers to the backend."
        )
    except Exception as e:
        pytest.fail(f"Failed to connect to proxy or proxy failed to forward: {e}")
    finally:
        server.shutdown()
        server.server_close()
        server_thread.join()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
