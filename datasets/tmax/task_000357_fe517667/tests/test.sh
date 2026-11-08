#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import signal
import socket
import socketserver
import threading
import time

import pytest
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad

PROXY = "/home/user/proxy"
SOURCE = "/home/user/proxy.c"
KEY = b"S3cr3tK3y1234567"
BACKEND_REQUESTS = []
BACKEND_LOCK = threading.Lock()


def test_proxy_executable_exists():
    assert os.path.isfile(PROXY), f"Proxy executable {PROXY} does not exist."
    assert os.access(PROXY, os.X_OK), f"Proxy executable {PROXY} is not executable."
    assert os.path.isfile(SOURCE), f"Proxy source {SOURCE} does not exist."
    with open(PROXY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Proxy is not a compiled native executable."


def test_proxy_is_listening():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    result = sock.connect_ex(("127.0.0.1", 8080))
    sock.close()
    assert result == 0, "Proxy service is not listening on 127.0.0.1:8080."


def _listener_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            found.add(fields[9])
        except OSError:
            pass
    return found


def _stop_existing_backend():
    inodes = _listener_inodes(8081)
    if not inodes:
        return
    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) in (1, os.getpid()):
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except OSError:
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and _listener_inodes(8081):
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


class BackendHandler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(2)
        data = b""
        while b"\r\n\r\n" not in data and len(data) < 65536:
            chunk = self.request.recv(4096)
            if not chunk:
                break
            data += chunk
        with BACKEND_LOCK:
            BACKEND_REQUESTS.append(data)
        body = b"BACKEND:" + hashlib.sha256(data).hexdigest().encode("ascii")
        response = (
            b"HTTP/1.1 200 OK\r\n"
            b"Content-Type: text/plain\r\n"
            b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n"
            b"Connection: close\r\n\r\n" + body
        )
        self.request.sendall(response)


class BackendServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def _cookie(plaintext, iv_byte):
    iv = bytes([iv_byte]) * 16
    ciphertext = AES.new(KEY, AES.MODE_CBC, iv).encrypt(pad(plaintext.encode(), 16))
    return (iv + ciphertext).hex()


def _invalid_padding_cookie(iv_byte):
    iv = bytes([iv_byte]) * 16
    ciphertext = AES.new(KEY, AES.MODE_CBC, iv).encrypt(b"A" * 15 + b"\x00")
    return (iv + ciphertext).hex()


def _exchange(request):
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=1.5) as s:
            s.settimeout(1.5)
            s.sendall(request)
            response = b""
            while len(response) < 131072:
                try:
                    part = s.recv(4096)
                except socket.timeout:
                    break
                if not part:
                    break
                response += part
        first = response.split(b"\r\n", 1)[0].split()
        status = int(first[1]) if len(first) >= 2 else None
        body = response.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in response else b""
        return status, body
    except (OSError, ValueError):
        return None, b""


def test_proxy_accuracy_metric():
    _stop_existing_backend()
    with BACKEND_LOCK:
        BACKEND_REQUESTS.clear()
    try:
        backend = BackendServer(("127.0.0.1", 8081), BackendHandler)
    except OSError as exc:
        pytest.fail(f"Could not start controlled backend on port 8081: {exc}")
    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()

    outcomes = []
    invalid_paths = []
    try:
        for i in range(50):
            path = f"/verification/case-{i}?value={i}"
            trace = f"trace-{i}-unchanged"
            valid = i % 2 == 0

            if valid:
                choices = [
                    "1000|admin|1800000000",
                    "42|user|1700000000",
                    "1000|admin|0",
                    "alice|auditor|-1",
                ]
                value = _cookie(choices[(i // 2) % len(choices)], i + 1)
                if i % 4 == 0:
                    value = value.upper()
                cookie_header = f"Cookie: foo=one; SecureSession={value}; theme=blue\r\n"
            else:
                kind = (i // 2) % 8
                if kind == 0:
                    cookie_header = ""
                elif kind == 1:
                    cookie_header = "Cookie: SecureSession=not-hex-data\r\n"
                elif kind == 2:
                    cookie_header = f"Cookie: SecureSession={_invalid_padding_cookie(i + 1)}\r\n"
                elif kind == 3:
                    cookie_header = f"Cookie: SecureSession={_cookie('999|admin|1700000000', i + 1)}\r\n"
                elif kind == 4:
                    cookie_header = f"Cookie: SecureSession={_cookie('01000|admin|1700000000', i + 1)}\r\n"
                elif kind == 5:
                    cookie_header = f"Cookie: SecureSession={_cookie('1000|user|1800000001', i + 1)}\r\n"
                elif kind == 6:
                    cookie_header = f"Cookie: SecureSession={_cookie('1000|user|notanumber', i + 1)}\r\n"
                else:
                    cookie_header = f"Cookie: SecureSession={_cookie('1000|user|1700000000|extra', i + 1)}\r\n"
                invalid_paths.append(path.encode())

            request = (
                f"GET {path} HTTP/1.1\r\n"
                f"Host: legacy.example\r\n"
                f"X-Verification-Trace: {trace}\r\n"
                f"{cookie_header}"
                f"Connection: close\r\n\r\n"
            ).encode("ascii")

            status, body = _exchange(request)
            if valid:
                expected_body = b"BACKEND:" + hashlib.sha256(request).hexdigest().encode("ascii")
                outcomes.append(status == 200 and body == expected_body)
            else:
                outcomes.append(status == 403)

        time.sleep(0.2)
        with BACKEND_LOCK:
            forwarded = list(BACKEND_REQUESTS)
        for path in invalid_paths:
            if any(req.startswith(b"GET " + path + b" HTTP/1.1\r\n") for req in forwarded):
                index = int(path.split(b"case-")[1].split(b"?")[0])
                outcomes[index] = False
    finally:
        backend.shutdown()
        backend.server_close()
        thread.join(timeout=2)

    accuracy = sum(outcomes) / len(outcomes)
    threshold = 0.98
    assert accuracy >= threshold, (
        f"Proxy accuracy is too low. Expected >= {threshold}, but got {accuracy:.3f} "
        f"({sum(outcomes)}/{len(outcomes)} cases passed)."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
