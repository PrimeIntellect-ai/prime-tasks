#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import json
import os
import secrets
import signal
import socket
import subprocess
import tempfile
import time

import pytest


def send_data(port, data):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect(('127.0.0.1', port))
        s.sendall(data)
        return s.recv(4096)
    except Exception:
        return b""
    finally:
        s.close()


def test_edge_proxy_behavior():
    proxy_script = '/home/user/edge_proxy.py'
    sensor_script = '/home/user/sensor_server.py'
    assert os.path.exists(proxy_script), f"{proxy_script} does not exist."

    # Replace the backend temporarily with an observable challenge backend. A
    # transparent proxy behaves identically, while fabricated ACK responses do not.
    with open(sensor_script, 'rb') as f:
        original_sensor = f.read()
    original_mode = os.stat(sensor_script).st_mode

    challenge_key = secrets.token_bytes(32)
    trace_path = tempfile.mktemp(prefix='sensor_trace_', dir='/tmp')
    backend_source = f'''import base64
import hashlib
import hmac
import socket

KEY = {challenge_key!r}
TRACE = {trace_path!r}

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 9090))
server.listen(5)
try:
    while True:
        client, _ = server.accept()
        try:
            data = client.recv(1024)
            if data:
                with open(TRACE, "ab") as trace:
                    trace.write(base64.b64encode(data) + b"\\n")
                if data == b"VALID_TEST":
                    response = b"SENSOR_ACK: " + data
                else:
                    digest = hmac.new(KEY, data, hashlib.sha256).hexdigest().encode()
                    response = b"BACKEND_CHALLENGE:" + digest + b":" + data
                client.sendall(response)
        finally:
            client.close()
finally:
    server.close()
'''
    with open(sensor_script, 'w') as f:
        f.write(backend_source)
    os.chmod(sensor_script, original_mode)

    # Instrument the real RotatingFileHandler constructor in the proxy process.
    audit_dir = tempfile.mkdtemp(prefix='handler_audit_', dir='/tmp')
    audit_path = os.path.join(audit_dir, 'calls.jsonl')
    with open(os.path.join(audit_dir, 'sitecustomize.py'), 'w') as f:
        f.write('''import json
import logging.handlers
import os

_RealRotatingFileHandler = logging.handlers.RotatingFileHandler

class AuditedRotatingFileHandler(_RealRotatingFileHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        path = os.environ.get("EDGE_HANDLER_AUDIT")
        if path:
            with open(path, "a") as out:
                out.write(json.dumps({
                    "filename": self.baseFilename,
                    "maxBytes": self.maxBytes,
                    "backupCount": self.backupCount
                }) + "\\n")

logging.handlers.RotatingFileHandler = AuditedRotatingFileHandler
''')

    for path in ('/home/user/proxy.log', '/home/user/proxy.log.1'):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['EDGE_HANDLER_AUDIT'] = audit_path
    env['PYTHONPATH'] = audit_dir + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')

    proxy_proc = subprocess.Popen(['python3', proxy_script], env=env)
    valid_payloads = []
    banned_payloads = []
    try:
        time.sleep(1.5)

        # Preserve the original fixed forwarding assertion.
        res_valid = send_data(8888, b"VALID_TEST")
        assert b"SENSOR_ACK: VALID_TEST" in res_valid, "Port forwarding failed for valid data. Expected 'SENSOR_ACK: VALID_TEST' in response."
        valid_payloads.append(b"VALID_TEST")

        # Exercise forwarding with unpredictable payloads and backend-derived replies.
        for i in range(5):
            payload = (f"VALID_{i}_" + secrets.token_hex(8)).encode()
            digest = hmac.new(challenge_key, payload, hashlib.sha256).hexdigest().encode()
            expected = b"BACKEND_CHALLENGE:" + digest + b":" + payload
            assert send_data(8888, payload) == expected, "Proxy did not transparently forward a randomized payload and backend response."
            valid_payloads.append(payload)

        # Preserve the original fixed firewall assertion.
        fixed_banned = b"HELLO BANNED_DEVICE 123"
        res_banned = send_data(8888, fixed_banned)
        assert res_banned == b"", "Firewall failed to drop the connection for banned payload. Expected empty response."
        banned_payloads.append(fixed_banned)

        # Test unpredictable banned payloads with the marker at varying offsets.
        for offset in (0, 7, 173, 700):
            payload = (secrets.token_hex(4).encode() * ((offset + 15) // 16))[:offset]
            payload += b"BANNED_DEVICE" + secrets.token_hex(9).encode()
            assert len(payload) <= 1024
            assert send_data(8888, payload) == b"", "A randomized banned payload was forwarded or answered."
            banned_payloads.append(payload)

        # Preserve the original rotation workload and assertions.
        for _ in range(10):
            payload = b"BANNED_DEVICE spam"
            banned_payloads.append(payload)
            send_data(8888, payload)
            time.sleep(0.1)

        assert os.path.exists('/home/user/proxy.log'), "/home/user/proxy.log not found. Logging may not be implemented."
        assert os.path.exists('/home/user/proxy.log.1'), "/home/user/proxy.log.1 not found. Log rotation may have failed."

        with open('/home/user/proxy.log', 'r') as f:
            log_content = f.read()
            assert "FIREWALL - Blocked connection" in log_content, "Correct log message 'FIREWALL - Blocked connection' not found in proxy.log."

        assert os.path.exists(audit_path), "RotatingFileHandler was not constructed."
        with open(audit_path) as f:
            handler_calls = [json.loads(line) for line in f if line.strip()]
        assert any(
            call.get('filename') == '/home/user/proxy.log'
            and call.get('maxBytes') == 200
            and call.get('backupCount') == 1
            for call in handler_calls
        ), "RotatingFileHandler must target proxy.log with maxBytes=200 and backupCount=1."

        # Confirm valid traffic reached the backend and blocked traffic did not.
        with open(trace_path, 'rb') as f:
            received = [base64.b64decode(line.strip()) for line in f if line.strip()]
        for payload in valid_payloads:
            assert payload in received, "Valid payload did not reach the sensor server."
        for payload in banned_payloads:
            assert payload not in received, "Banned payload was forwarded to the sensor server."

        # Preserve the original process lifecycle assertions.
        pgrep = subprocess.run(['pgrep', '-f', 'sensor_server.py'], stdout=subprocess.PIPE)
        assert pgrep.returncode == 0, "sensor_server.py child process not found. The proxy should supervise this process."

        proxy_proc.send_signal(signal.SIGTERM)
        try:
            proxy_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proxy_proc.kill()
            pytest.fail("edge_proxy.py did not exit within 5 seconds after receiving SIGTERM.")

        time.sleep(0.5)
        pgrep_after = subprocess.run(['pgrep', '-f', 'sensor_server.py'], stdout=subprocess.PIPE)
        assert pgrep_after.returncode != 0, "sensor_server.py was not terminated by the supervisor upon SIGTERM."

    finally:
        if proxy_proc.poll() is None:
            proxy_proc.kill()
            proxy_proc.wait()
        subprocess.run(['pkill', '-f', 'sensor_server.py'])
        with open(sensor_script, 'wb') as f:
            f.write(original_sensor)
        os.chmod(sensor_script, original_mode)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
