#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import queue
import secrets
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request

import pytest


def adler32(data: str) -> int:
    a = 1
    b = 0
    for char in data:
        c = ord(char)
        a = (a + c) % 65521
        b = (b + a) % 65521
    return (b << 16) | a


def is_port_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        return s.connect_ex(('127.0.0.1', port)) == 0


def send_request(uri: str, checksum: str = None):
    req = urllib.request.Request(f"http://127.0.0.1:8080{uri}")
    if checksum is not None:
        req.add_header("X-Secure-Checksum", checksum)
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            return response.status, response.read().decode('utf-8', errors='ignore')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', errors='ignore')
    except Exception as e:
        return 0, str(e)


def listener_pid(port: int):
    wanted_inode = None
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == '0A' and int(local.rsplit(':', 1)[1], 16) == port:
                        wanted_inode = fields[9]
                        break
        except OSError:
            pass
        if wanted_inode:
            break
    if not wanted_inode:
        return None

    target = f'socket:[{wanted_inode}]'
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f'{fd_dir}/{fd}') == target:
                        return int(name)
                except OSError:
                    pass
        except OSError:
            pass
    return None


def raw_exchange(request: bytes, timeout=3) -> bytes:
    with socket.create_connection(('127.0.0.1', 8080), timeout=timeout) as s:
        s.settimeout(timeout)
        s.sendall(request)
        s.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
        return b''.join(chunks)


def wait_port(port: int, open_state: bool, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if is_port_open(port) == open_state:
            return True
        time.sleep(0.05)
    return False


class CaptureBackend:
    def __init__(self):
        self.requests = queue.Queue()
        self.responses = queue.Queue()
        self.stop_event = threading.Event()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(('127.0.0.1', 9090))
        self.sock.listen(20)
        self.sock.settimeout(0.1)
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.thread.start()

    def _run(self):
        while not self.stop_event.is_set():
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with conn:
                conn.settimeout(2)
                data = bytearray()
                try:
                    while b'\r\n\r\n' not in data:
                        chunk = conn.recv(65536)
                        if not chunk:
                            break
                        data.extend(chunk)
                    body = self.responses.get(timeout=2)
                    self.requests.put(bytes(data))
                    response = (
                        b'HTTP/1.1 200 OK\r\n'
                        + f'Content-Length: {len(body)}\r\n'.encode()
                        + b'Connection: close\r\n\r\n'
                        + body
                    )
                    conn.sendall(response)
                except Exception as exc:
                    self.requests.put(exc)

    def stop(self):
        self.stop_event.set()
        try:
            self.sock.close()
        except OSError:
            pass
        self.thread.join(timeout=1)


def test_ports_listening():
    assert is_port_open(9090), "Mock backend is not listening on port 9090."
    assert is_port_open(8080), "Security proxy is not listening on port 8080."


def test_required_artifacts_and_listener_types():
    source = '/home/user/secure_proxy.c'
    binary = '/home/user/secure_proxy'
    backend = '/home/user/mock_backend.py'
    assert os.path.isfile(source), f'{source} does not exist.'
    assert os.path.isfile(backend), f'{backend} does not exist.'
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), f'{binary} is not executable.'
    with open(binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'secure_proxy is not a compiled native executable.'

    proxy_pid = listener_pid(8080)
    assert proxy_pid is not None, 'Could not identify the process listening on port 8080.'
    assert os.path.samefile(f'/proc/{proxy_pid}/exe', binary), 'Port 8080 is not served by /home/user/secure_proxy.'

    backend_pid = listener_pid(9090)
    assert backend_pid is not None, 'Could not identify the process listening on port 9090.'
    with open(f'/proc/{backend_pid}/cmdline', 'rb') as f:
        cmdline = f.read().replace(b'\x00', b' ')
    assert backend.encode() in cmdline, 'Port 9090 is not served by /home/user/mock_backend.py.'


def test_mock_backend_general_get_behavior():
    path = '/backend-' + secrets.token_hex(10)
    with urllib.request.urlopen(f'http://127.0.0.1:9090{path}', timeout=2) as response:
        assert response.status == 200
        assert response.read() == b'Authorized Backend Data\n'


def test_proxy_missing_checksum():
    status, body = send_request("/test")
    assert status == 403, f"Expected 403 Forbidden for missing checksum, got {status}."


def test_proxy_valid_checksum():
    uri = "/api/data"
    checksum = str(adler32(uri))
    status, body = send_request(uri, checksum)
    assert status == 200, f"Expected 200 OK for valid checksum, got {status}."
    assert "Authorized Backend Data" in body, "Response body did not match expected backend data."


def test_proxy_invalid_checksum():
    uri = "/api/data"
    status, body = send_request(uri, "12345")
    assert status == 403, f"Expected 403 Forbidden for invalid checksum, got {status}."


def test_proxy_log_contents():
    log_path = "/home/user/proxy.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    time.sleep(0.5)
    with open(log_path, 'r') as f:
        logs = f.read()

    expected_lines = [
        "[DENY] /test NONE",
        f"[ALLOW] /api/data {adler32('/api/data')}",
        "[DENY] /api/data 12345"
    ]

    for line in expected_lines:
        assert line in logs, f"Expected log line '{line}' not found in {log_path}."


def test_randomized_checksum_forwarding_and_logs():
    backend_pid = listener_pid(9090)
    assert backend_pid is not None
    os.kill(backend_pid, 15)
    if not wait_port(9090, False):
        try:
            os.kill(backend_pid, 9)
        except ProcessLookupError:
            pass
        assert wait_port(9090, False), 'Could not stop the mock backend for forwarding verification.'

    capture = None
    restarted = None
    expected_logs = []
    try:
        capture = CaptureBackend()
        capture.start()

        for index in range(5):
            path = '/probe-' + secrets.token_hex(8) + '/item-' + secrets.token_hex(5)
            query = 'nonce=' + secrets.token_hex(7)
            target = f'{path}?{query}'
            checksum = str(adler32(path))
            marker = secrets.token_hex(12)
            body = f'captured-{index}-{marker}\n'.encode()
            capture.responses.put(body)
            request = (
                f'GET {target} HTTP/1.1\r\n'
                f'Host: 127.0.0.1:8080\r\n'
                f'X-Secure-Checksum: {checksum}\r\n'
                f'X-Random-Probe: {marker}\r\n'
                f'Connection: close\r\n\r\n'
            ).encode()
            response = raw_exchange(request)
            assert response.startswith(b'HTTP/1.1 200'), f'Valid randomized request was not allowed: {response!r}'
            assert response.split(b'\r\n\r\n', 1)[1] == body, 'Proxy did not return the capture backend response exactly.'
            forwarded = capture.requests.get(timeout=2)
            assert not isinstance(forwarded, Exception), f'Capture backend failed: {forwarded}'
            assert forwarded == request, 'Proxy did not forward the exact raw HTTP request.'
            expected_logs.append(f'[ALLOW] {path} {checksum}')

            bad_path = '/denied-' + secrets.token_hex(11)
            correct = adler32(bad_path)
            wrong = str((correct + 1) & 0xffffffff)
            bad_request = (
                f'GET {bad_path} HTTP/1.1\r\n'
                f'Host: 127.0.0.1:8080\r\n'
                f'X-Secure-Checksum: {wrong}\r\n'
                f'Connection: close\r\n\r\n'
            ).encode()
            denied = raw_exchange(bad_request)
            assert denied == b'HTTP/1.1 403 Forbidden\r\n\r\n', 'Invalid checksum did not receive the required exact 403 response.'
            expected_logs.append(f'[DENY] {bad_path} {wrong}')

            missing_path = '/missing-' + secrets.token_hex(9)
            missing_request = (
                f'GET {missing_path} HTTP/1.1\r\n'
                f'Host: 127.0.0.1:8080\r\n'
                f'Connection: close\r\n\r\n'
            ).encode()
            denied = raw_exchange(missing_request)
            assert denied == b'HTTP/1.1 403 Forbidden\r\n\r\n', 'Missing checksum did not receive the required exact 403 response.'
            expected_logs.append(f'[DENY] {missing_path} NONE')

        time.sleep(0.3)
        assert capture.requests.empty(), 'An invalid or missing-checksum request was forwarded to the backend.'
        with open('/home/user/proxy.log') as f:
            logs = f.read()
        for line in expected_logs:
            assert line in logs, f"Expected randomized log line '{line}' was not written."
    finally:
        if capture is not None:
            capture.stop()
        restarted = subprocess.Popen(
            ['python3', '/home/user/mock_backend.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        assert wait_port(9090, True), 'Mock backend was not restored on port 9090.'

    assert is_port_open(8080), 'Security proxy stopped running during verification.'
    assert is_port_open(9090), 'Mock backend is not running after verification.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
