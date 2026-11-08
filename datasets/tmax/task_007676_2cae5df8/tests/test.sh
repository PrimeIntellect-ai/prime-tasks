#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import ctypes
import os
import re
import secrets
import socket
import struct
import subprocess

import pytest

WORKSPACE = "/home/user/workspace"
LIB_PATH = f"{WORKSPACE}/lib/libparser.so"
SERVER_PATH = f"{WORKSPACE}/backend/server.py"
NGINX_PATH = f"{WORKSPACE}/nginx/nginx.conf"
LOG_PATH = f"{WORKSPACE}/integration_results.log"
TEST_PATH = f"{WORKSPACE}/test_integration.py"


def _read_exact(sock, buffered, count):
    while len(buffered) < count:
        chunk = sock.recv(max(4096, count - len(buffered)))
        if not chunk:
            raise AssertionError("WebSocket connection closed unexpectedly")
        buffered += chunk
    return buffered[:count], buffered[count:]


def _send_frame(sock, opcode, payload):
    if isinstance(payload, str):
        payload = payload.encode("utf-8")
    mask = secrets.token_bytes(4)
    length = len(payload)
    header = bytes([0x80 | opcode])
    if length < 126:
        header += bytes([0x80 | length])
    elif length < 65536:
        header += bytes([0x80 | 126]) + struct.pack("!H", length)
    else:
        header += bytes([0x80 | 127]) + struct.pack("!Q", length)
    masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    sock.sendall(header + mask + masked)


class RawWebSocket:
    def __init__(self, sock, buffered=b""):
        self.sock = sock
        self.buffered = buffered

    def send_text(self, text):
        _send_frame(self.sock, 0x1, text)

    def receive_text(self):
        fragments = []
        while True:
            first, self.buffered = _read_exact(self.sock, self.buffered, 2)
            fin = bool(first[0] & 0x80)
            opcode = first[0] & 0x0f
            masked = bool(first[1] & 0x80)
            length = first[1] & 0x7f
            if length == 126:
                raw, self.buffered = _read_exact(self.sock, self.buffered, 2)
                length = struct.unpack("!H", raw)[0]
            elif length == 127:
                raw, self.buffered = _read_exact(self.sock, self.buffered, 8)
                length = struct.unpack("!Q", raw)[0]
            mask = b""
            if masked:
                mask, self.buffered = _read_exact(self.sock, self.buffered, 4)
            data, self.buffered = _read_exact(self.sock, self.buffered, length)
            if masked:
                data = bytes(value ^ mask[index % 4] for index, value in enumerate(data))
            if opcode == 0x8:
                raise AssertionError("Server closed before returning a message")
            if opcode == 0x9:
                _send_frame(self.sock, 0xA, data)
                continue
            if opcode in (0x0, 0x1):
                fragments.append(data)
                if fin:
                    return b"".join(fragments).decode("utf-8")

    def close(self):
        try:
            _send_frame(self.sock, 0x8, b"")
        except OSError:
            pass
        self.sock.close()


def websocket_handshake(port, version):
    sock = socket.create_connection(("127.0.0.1", port), timeout=4)
    sock.settimeout(6)
    key = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
    headers = [
        "GET / HTTP/1.1",
        f"Host: 127.0.0.1:{port}",
        "Upgrade: websocket",
        "Connection: Upgrade",
        f"Sec-WebSocket-Key: {key}",
        "Sec-WebSocket-Version: 13",
    ]
    if version is not None:
        headers.append(f"X-API-Version: {version}")
    request = "\r\n".join(headers) + "\r\n\r\n"
    sock.sendall(request.encode("ascii"))

    response = b""
    while b"\r\n\r\n" not in response:
        chunk = sock.recv(4096)
        if not chunk:
            break
        response += chunk
        assert len(response) < 65536, "Unreasonably large HTTP handshake response"
    head, separator, tail = response.partition(b"\r\n\r\n")
    assert separator, "Server did not return a complete HTTP handshake response"
    lines = head.decode("latin-1").split("\r\n")
    match = re.match(r"HTTP/\d(?:\.\d)?\s+(\d{3})", lines[0])
    assert match, f"Invalid HTTP status line: {lines[0]!r}"
    status = int(match.group(1))
    response_headers = {}
    for line in lines[1:]:
        if ":" in line:
            name, value = line.split(":", 1)
            response_headers[name.strip().lower()] = value.strip()
    if status == 101:
        return status, response_headers, RawWebSocket(sock, tail)
    sock.close()
    return status, response_headers, None


def assert_rejected(port, version):
    status, _, ws = websocket_handshake(port, version)
    if ws:
        ws.close()
    assert status == 403, f"Version {version!r} on port {port} returned HTTP {status}, expected 403"


def assert_echo(port, version, payload, require_nginx=False):
    status, headers, ws = websocket_handshake(port, version)
    assert status == 101, f"Version {version!r} on port {port} returned HTTP {status}, expected 101"
    assert ws is not None
    if require_nginx:
        assert "nginx" in headers.get("server", "").lower(), "Port 8080 handshake was not served through Nginx"
    try:
        ws.send_text(payload)
        response = ws.receive_text()
        assert response == "{PROCESSED: " + payload + "}"
    finally:
        ws.close()


def test_libparser_so_exists():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not built or is missing."
    with open(LIB_PATH, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "libparser.so is not an ELF shared library"


def test_c_library_is_loadable_and_safe_for_large_dynamic_input():
    library = ctypes.CDLL(LIB_PATH)
    parse = library.parse_message
    parse.argtypes = [ctypes.c_char_p]
    parse.restype = ctypes.c_void_p
    payload = ("C-parser-" + secrets.token_hex(32) + "Z" * 200000).encode("ascii")
    pointer = parse(payload)
    assert pointer, "parse_message returned NULL"
    try:
        assert ctypes.string_at(pointer) == b"{PROCESSED: " + payload + b"}"
    finally:
        try:
            free_message = library.free_message
        except AttributeError:
            libc = ctypes.CDLL(None)
            libc.free.argtypes = [ctypes.c_void_p]
            libc.free(pointer)
        else:
            free_message.argtypes = [ctypes.c_void_p]
            free_message.restype = None
            free_message(pointer)


def test_required_source_and_configuration_files():
    assert os.path.isfile(SERVER_PATH), "backend/server.py is missing"
    assert os.path.isfile(NGINX_PATH), "nginx/nginx.conf is missing"
    assert os.path.isfile(TEST_PATH), "test_integration.py is missing"

    server = open(SERVER_PATH, encoding="utf-8").read()
    assert "ctypes" in server and "CDLL" in server, "server.py does not load the C library with ctypes"
    assert "libparser.so" in server and "parse_message" in server, "server.py does not call libparser.so parse_message"
    assert "X-API-Version" in server, "server.py does not inspect X-API-Version"
    assert "free_message" in server or re.search(r"\bfree\s*\(", server), "server.py does not free the C result"

    nginx = open(NGINX_PATH, encoding="utf-8").read()
    nginx = re.sub(r"#.*", "", nginx)
    assert re.search(r"\blisten\s+[^;]*\b8080\b[^;]*;", nginx), "Nginx config does not listen on 8080"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:9000\s*;", nginx), "Nginx config does not proxy to 127.0.0.1:9000"
    assert re.search(r"\bproxy_set_header\s+Upgrade\s+\$http_upgrade\s*;", nginx, re.I), "Nginx config does not pass Upgrade"
    assert re.search(r"\bproxy_set_header\s+Connection\s+[^;]+;", nginx, re.I), "Nginx config does not pass Connection"


def test_submitted_integration_test_recreates_log():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    result = subprocess.run(
        ["python3", TEST_PATH], cwd=WORKSPACE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=35
    )
    assert result.returncode == 0, f"Integration test failed:\n{result.stdout}"
    assert os.path.isfile(LOG_PATH), "Integration test did not create integration_results.log"


def test_integration_results_log():
    assert os.path.isfile(LOG_PATH), f"Integration log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) >= 2, "Log file does not have the expected number of lines."
    assert "VERSION_REJECTED" in lines[0], "First line does not contain 'VERSION_REJECTED'."
    expected_success = "SUCCESS: {PROCESSED: " + ("A" * 500) + "}"
    assert expected_success in lines[1], "Second line does not contain the expected SUCCESS message with 500 'A's."


def test_semantic_versions_and_backend_c_processing_directly():
    for invalid in (None, "1.9.9", "2.0.999", "2.1.0-rc.1", "3.0.0", "3.1.0", "not-a-version", "2.1"):
        assert_rejected(9000, invalid)
    assert_echo(9000, "2.1.0", "direct-" + secrets.token_hex(20))
    assert_echo(9000, "2.10.0", "ordering-" + secrets.token_hex(20))
    assert_echo(9000, "2.1.0+build.7", "build-metadata-" + secrets.token_hex(20))


def test_nginx_websocket_proxy_and_large_random_payload():
    for invalid in ("1.9.9", "2.1.0-alpha", "3.0.0", "garbage"):
        assert_rejected(8080, invalid)
    payload = "gateway-" + secrets.token_hex(48) + ("A" * 12000)
    assert_echo(8080, "2.5.0", payload, require_nginx=True)


def test_nginx_running_port_8080():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        result = s.connect_ex(("127.0.0.1", 8080))
        assert result == 0, "Nothing is listening on port 8080 (expected Nginx)."
    result = subprocess.run(["pgrep", "-x", "nginx"], stdout=subprocess.PIPE)
    assert result.returncode == 0, "No Nginx process is running"


def test_backend_running_port_9000():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        result = s.connect_ex(("127.0.0.1", 9000))
        assert result == 0, "Nothing is listening on port 9000 (expected Python backend)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
