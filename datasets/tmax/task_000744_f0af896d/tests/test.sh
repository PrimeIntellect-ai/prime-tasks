#!/bin/bash
set -e
mkdir -p /logs/verifier
chmod +x /tests/sanitizer_oracle

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import socket
import subprocess
import tempfile
import threading
import time

import pytest

AGENT_BIN = "/home/user/workspace/sanitizer"
AGENT_SRC = "/home/user/workspace/sanitizer.cpp"
ORACLE_BIN = "/tests/sanitizer_oracle"
NGINX_CONFIG = "/home/user/workspace/nginx.conf"


def run_program(path, data, timeout=2):
    return subprocess.run([path], input=data, capture_output=True, timeout=timeout)


def test_sanitizer_fuzz_equivalence():
    assert os.path.isfile(AGENT_SRC), f"C++ source not found at {AGENT_SRC}"
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"

    with open(AGENT_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sanitizer must be a compiled executable"

    assert hashlib.sha256(open(AGENT_BIN, "rb").read()).digest() != hashlib.sha256(open(ORACLE_BIN, "rb").read()).digest(), (
        "Submitted sanitizer is byte-identical to the reference oracle"
    )

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "sanitizer")
        compile_proc = subprocess.run(
            ["g++", "-O3", AGENT_SRC, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_proc.returncode == 0, f"sanitizer.cpp failed to compile:\n{compile_proc.stderr}"

        source_rng = random.Random(314159)
        for i in range(100):
            length = source_rng.randint(0, 4096)
            input_data = bytes(source_rng.choices(range(256), k=length))
            try:
                oracle_proc = run_program(ORACLE_BIN, input_data)
                rebuilt_proc = run_program(rebuilt, input_data)
            except subprocess.TimeoutExpired:
                pytest.fail(f"Rebuilt sanitizer timed out on source test {i}")
            assert rebuilt_proc.returncode == oracle_proc.returncode, f"Rebuilt source return-code mismatch on test {i}"
            assert rebuilt_proc.stdout == oracle_proc.stdout, f"Rebuilt source output mismatch on test {i}"

    random.seed(42)
    for i in range(1000):
        length = random.randint(0, 4096)
        input_data = bytes(random.choices(range(256), k=length))
        try:
            oracle_proc = run_program(ORACLE_BIN, input_data)
            agent_proc = run_program(AGENT_BIN, input_data)
        except subprocess.TimeoutExpired:
            pytest.fail(f"Timeout on input iteration {i} (length {length})")

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Return code mismatch on iteration {i}. "
            f"Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"
        )
        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on iteration {i} (length {length}).\n"
            f"Oracle output: {oracle_proc.stdout!r}\n"
            f"Agent output: {agent_proc.stdout!r}"
        )


def make_backend(response):
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(10)
    port = listener.getsockname()[1]
    captured = {}

    def worker():
        try:
            conn, _ = listener.accept()
            conn.settimeout(5)
            data = b""
            while b"\r\n\r\n" not in data and len(data) < 65536:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            captured["request"] = data
            conn.sendall(response)
            conn.close()
        except Exception as exc:
            captured["error"] = repr(exc)
        finally:
            listener.close()

    thread = threading.Thread(target=worker, daemon=True)
    thread.start()
    return port, captured, thread


def send_request(request):
    sock = socket.create_connection(("127.0.0.1", 8080), timeout=5)
    sock.settimeout(5)
    sock.sendall(request)
    data = b""
    while True:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            break
        if not chunk:
            break
        data += chunk
    sock.close()
    return data


def parse_request(raw):
    lines = raw.decode("latin1").split("\r\n")
    request_line = lines[0]
    headers = {}
    for line in lines[1:]:
        if not line:
            break
        name, value = line.split(":", 1)
        headers[name.lower()] = value.strip()
    return request_line, headers


def test_nginx_configuration():
    assert os.path.exists(NGINX_CONFIG), f"Nginx config not found at {NGINX_CONFIG}"

    with open(NGINX_CONFIG, "r") as f:
        content = f.read()

    # Retain the original directive checks.
    assert "5000" in content, "Missing proxy_pass to port 5000 for the REST API."
    assert "5001" in content, "Missing proxy_pass to port 5001 for the WebSocket service."
    content_lower = content.lower()
    assert "upgrade $http_upgrade" in content_lower, "Missing 'proxy_set_header Upgrade $http_upgrade;' directive."
    assert "connection" in content_lower and "upgrade" in content_lower, "Missing 'proxy_set_header Connection \"upgrade\";' directive."
    assert "host" in content_lower and "$host" in content_lower, "Missing 'proxy_set_header Host $host;' (or similar) directive."

    syntax = subprocess.run(["nginx", "-t", "-c", NGINX_CONFIG], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Invalid Nginx configuration:\n{syntax.stderr}"

    api_response = b"HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nAPI_OK"
    ws_response = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"

    api_port, api_capture, api_thread = make_backend(api_response)
    ws_port, ws_capture, ws_thread = make_backend(ws_response)
    assert api_port != 5000 and ws_port != 5001

    # Forward temporary local ports to the required fixed backend ports.
    api_forward = subprocess.Popen(["socat", f"TCP-LISTEN:5000,bind=127.0.0.1,reuseaddr,fork", f"TCP:127.0.0.1:{api_port}"])
    ws_forward = subprocess.Popen(["socat", f"TCP-LISTEN:5001,bind=127.0.0.1,reuseaddr,fork", f"TCP:127.0.0.1:{ws_port}"])
    nginx_proc = None
    try:
        time.sleep(0.2)
        nginx_proc = subprocess.Popen(
            ["nginx", "-c", NGINX_CONFIG, "-g", "daemon off; pid /tmp/task-nginx.pid;"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        time.sleep(0.5)
        assert nginx_proc.poll() is None, "Nginx failed to start with the submitted configuration"

        api_result = send_request(
            b"GET /api/check?x=1 HTTP/1.1\r\nHost: original.example\r\nConnection: close\r\n\r\n"
        )
        assert b"200 OK" in api_result and b"API_OK" in api_result, "REST request did not reach the backend"
        api_thread.join(5)
        assert "error" not in api_capture, api_capture.get("error")
        api_line, api_headers = parse_request(api_capture["request"])
        assert api_line.startswith("GET /api/check?x=1 "), f"Unexpected REST path: {api_line}"
        assert api_headers.get("host") == "original.example", "REST upstream did not preserve the Host header"

        ws_result = send_request(
            b"GET /stream/socket HTTP/1.1\r\n"
            b"Host: original.example\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n"
            b"Sec-WebSocket-Version: 13\r\n"
            b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
        )
        assert b"101 Switching Protocols" in ws_result, "WebSocket handshake did not reach the backend"
        ws_thread.join(5)
        assert "error" not in ws_capture, ws_capture.get("error")
        ws_line, ws_headers = parse_request(ws_capture["request"])
        assert ws_line.startswith("GET /stream/socket "), f"Unexpected WebSocket path: {ws_line}"
        assert ws_headers.get("host") == "original.example", "WebSocket upstream did not preserve the Host header"
        assert ws_headers.get("upgrade", "").lower() == "websocket", "Upgrade header was not forwarded"
        assert "upgrade" in ws_headers.get("connection", "").lower(), "Connection upgrade header was not forwarded"
    finally:
        for proc in (nginx_proc, api_forward, ws_forward):
            if proc is not None and proc.poll() is None:
                proc.terminate()
        for proc in (nginx_proc, api_forward, ws_forward):
            if proc is not None:
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
