#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import queue
import secrets
import signal
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import requests

APP_COMMANDS = (
    b'/app/startup.sh',
    b'/app/ingester.py',
    b'/app/validator.py',
    b'/app/storage.py',
)


def kill_app_services():
    me = os.getpid()
    victims = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmdline = f.read()
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if any(command in cmdline for command in APP_COMMANDS):
            victims.append(int(entry))

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.3)


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError(f'Port {port} did not start listening')


def listening_ipv4_addresses(port):
    result = []
    with open('/proc/net/tcp', 'r') as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, local_port = fields[1].split(':')
            state = fields[3]
            if int(local_port, 16) == port and state == '0A':
                result.append(local_address.upper())
    return result


def assert_runtime_binding(script, port, expected_address):
    kill_app_services()
    proc = subprocess.Popen(
        ['python3', script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_port(port)
        addresses = listening_ipv4_addresses(port)
        assert addresses, f'No IPv4 listener found for {script} on port {port}'
        assert expected_address in addresses, (
            f'{script} did not listen on the required address on port {port}: {addresses}'
        )
        assert all(address == expected_address for address in addresses), (
            f'{script} has an unexpected listening interface on port {port}: {addresses}'
        )
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
        kill_app_services()


def audit_seed():
    matches = []
    with open('/app/logs/security.log', 'r') as f:
        for line in f:
            if 'EventID=4421' in line and 'Status=AuditMode' in line:
                fields = {}
                for item in line.split():
                    if '=' in item:
                        key, value = item.split('=', 1)
                        fields[key] = value
                if 'AuditKey' in fields:
                    matches.append(fields['AuditKey'])
    assert len(matches) == 1, 'Expected exactly one AuditMode EventID=4421 with an AuditKey'
    return base64.b64decode(matches[0], validate=True).decode('utf-8')


def expected_token(body):
    seed = audit_seed()
    return hashlib.sha256(f'{seed}:{len(body)}'.encode('utf-8')).hexdigest()


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def start_capture_server(port, response_status, response_body):
    captured = queue.Queue()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            body = self.rfile.read(length)
            captured.put({
                'path': self.path,
                'body': body,
                'headers': {k.lower(): v for k, v in self.headers.items()},
            })
            encoded = response_body.encode('utf-8')
            self.send_response(response_status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

        def log_message(self, *args):
            pass

    server = ReusableHTTPServer(('127.0.0.1', port), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread, captured


def test_validator_bindings():
    assert os.path.isfile('/app/validator.py'), '/app/validator.py is missing'
    with open('/app/validator.py', 'r') as f:
        content = f.read()
        assert '127.0.0.1' in content, 'Validator source code does not contain 127.0.0.1 binding.'
        assert '0.0.0.0' not in content, 'Validator source code still contains 0.0.0.0 binding, exposing it to the network.'
    assert_runtime_binding('/app/validator.py', 5001, '0100007F')


def test_storage_bindings():
    assert os.path.isfile('/app/storage.py'), '/app/storage.py is missing'
    with open('/app/storage.py', 'r') as f:
        content = f.read()
        assert '127.0.0.1' in content, 'Storage source code does not contain 127.0.0.1 binding.'
        assert '0.0.0.0' not in content, 'Storage source code still contains 0.0.0.0 binding, exposing it to the network.'
    assert_runtime_binding('/app/storage.py', 5002, '0100007F')


def test_ingester_runtime_binding():
    assert os.path.isfile('/app/ingester.py'), '/app/ingester.py is missing'
    assert_runtime_binding('/app/ingester.py', 5000, '00000000')


def test_end_to_end_flow():
    kill_app_services()
    assert os.path.isfile('/app/startup.sh'), '/app/startup.sh is missing'
    assert os.access('/app/startup.sh', os.X_OK), '/app/startup.sh is not executable'
    proc = subprocess.Popen(
        ['/app/startup.sh'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_port(5000)
        wait_for_port(5001)
        wait_for_port(5002)
        assert listening_ipv4_addresses(5000) == ['00000000'], 'Ingester is not bound only to 0.0.0.0:5000'
        assert listening_ipv4_addresses(5001) == ['0100007F'], 'Validator is not bound only to 127.0.0.1:5001'
        assert listening_ipv4_addresses(5002) == ['0100007F'], 'Storage is not bound only to 127.0.0.1:5002'

        payload = {'test': secrets.token_hex(24), 'count': secrets.randbelow(1000000)}
        response = requests.post('http://127.0.0.1:5000/ingest', json=payload, timeout=5)
        assert response.status_code == 200, f'Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text}'
        data = response.json()
        assert data.get('status') == 'stored', f"Expected response JSON to contain {{'status': 'stored'}}, got {data}"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
        kill_app_services()


def test_ingester_computes_token_and_forwards_exact_payload():
    kill_app_services()
    marker = secrets.token_hex(20)
    response_body = json.dumps({'validator_marker': marker})
    server, thread, captured = start_capture_server(5001, 202, response_body)
    proc = subprocess.Popen(
        ['python3', '/app/ingester.py'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_port(5000)
        raw = json.dumps({
            'nonce': secrets.token_hex(32),
            'value': secrets.randbelow(2**31),
        }, separators=(',', ':')).encode('utf-8')
        response = requests.post(
            'http://127.0.0.1:5000/ingest',
            data=raw,
            headers={'Content-Type': 'application/json'},
            timeout=5,
        )
        assert response.status_code == 202, 'Ingester did not propagate the mock Validator response status'
        assert response.json() == {'validator_marker': marker}, 'Ingester did not propagate the mock Validator response body'
        forwarded = captured.get(timeout=3)
        assert forwarded['path'] == '/validate', 'Ingester did not call the Validator /validate endpoint'
        assert forwarded['body'] == raw, 'Ingester changed or failed to forward the payload'
        assert forwarded['headers'].get('x-audit-token') == expected_token(raw), 'Ingester sent an incorrect X-Audit-Token'
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        kill_app_services()


def test_validator_checks_token_and_forwards_to_storage():
    kill_app_services()
    marker = secrets.token_hex(20)
    response_body = json.dumps({'storage_marker': marker})
    server, thread, captured = start_capture_server(5002, 200, response_body)
    proc = subprocess.Popen(
        ['python3', '/app/validator.py'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_port(5001)
        raw = json.dumps({'audit': secrets.token_hex(30)}, separators=(',', ':')).encode('utf-8')
        bad = requests.post(
            'http://127.0.0.1:5001/validate',
            data=raw,
            headers={'Content-Type': 'application/json', 'X-Audit-Token': secrets.token_hex(32)},
            timeout=5,
        )
        assert bad.status_code == 403, 'Validator accepted an invalid audit token'

        good = requests.post(
            'http://127.0.0.1:5001/validate',
            data=raw,
            headers={'Content-Type': 'application/json', 'X-Audit-Token': expected_token(raw)},
            timeout=5,
        )
        assert good.status_code == 200, 'Validator rejected the independently derived audit token'
        assert good.json() == {'storage_marker': marker}, 'Validator did not propagate the Storage response'
        forwarded = captured.get(timeout=3)
        assert forwarded['path'] == '/store', 'Validator did not call the Storage /store endpoint'
        assert forwarded['body'] == raw, 'Validator changed or failed to forward the payload'
        assert captured.empty(), 'Validator forwarded more than the single valid request'
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        kill_app_services()


def test_storage_service_response():
    kill_app_services()
    proc = subprocess.Popen(
        ['python3', '/app/storage.py'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_port(5002)
        response = requests.post(
            'http://127.0.0.1:5002/store',
            json={'nonce': secrets.token_hex(24)},
            timeout=5,
        )
        assert response.status_code == 200
        assert response.json().get('status') == 'stored'
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
        kill_app_services()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
