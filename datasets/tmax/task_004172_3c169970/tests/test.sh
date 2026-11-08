#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import signal
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest


def wait_port(port, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError(f"127.0.0.1:{port} did not begin listening")


def raw_http(port, body=b"", path="/", timeout=3):
    request = (
        f"POST {path} HTTP/1.1\r\n"
        f"Host: 127.0.0.1\r\n"
        f"Content-Type: application/json\r\n"
        f"Content-Length: {len(body)}\r\n"
        f"Connection: close\r\n\r\n"
    ).encode() + body
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(request)
        chunks = []
        while True:
            try:
                chunk = sock.recv(65536)
            except (socket.timeout, ConnectionResetError):
                break
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks)


def stop_group(proc):
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=4)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=4)


def test_filter_corpus_and_generated_cases():
    filter_src = "/app/proxy/filter.c"
    assert os.path.isfile(filter_src), f"Missing filter source file at {filter_src}"

    lib_path = "/tmp/libfilter.so"
    compile_cmd = ["gcc", "-shared", "-fPIC", filter_src, "-o", lib_path]
    try:
        subprocess.run(compile_cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compile filter.c:\n{e.stderr}")

    lib = ctypes.CDLL(lib_path)
    validate_payload = lib.validate_payload
    validate_payload.argtypes = [ctypes.c_char_p]
    validate_payload.restype = ctypes.c_int

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for f in clean_files:
        with open(os.path.join(clean_dir, f), "rb") as fd:
            if validate_payload(fd.read()) != 0:
                clean_failed.append(f)

    evil_failed = []
    for f in evil_files:
        with open(os.path.join(evil_dir, f), "rb") as fd:
            if validate_payload(fd.read()) != 1:
                evil_failed.append(f)

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed[:10])}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified: {', '.join(clean_failed[:10])}")
    if errors:
        pytest.fail(" | ".join(errors))

    nonce = random.SystemRandom().randrange(100000, 999999)
    generated_clean = [
        f'{{"username":"visitor_{nonce}","age":31}}',
        f'{{"message":"meeting at noon {nonce}","active":true}}',
        f'{{"product":"selection box","delivery":"dropoff {nonce}"}}',
        f'{{"note":"ordinary punctuation: hello, world!","id":{nonce}}}',
    ]
    generated_evil = [
        f'{{"user":"admin\' OR {nonce}={nonce} -- "}}',
        f'{{"q":"x UnIoN SeLeCt password FROM users -- {nonce}"}}',
        f'{{"name":"x; /bin/sh -c id # {nonce}"}}',
        f'{{"name":"$(whoami)-{nonce}"}}',
        f'{{"html":"<ScRiPt>alert({nonce})</sCrIpT>"}}',
        f'{{"html":"<img src=x onerror=alert({nonce})>"}}',
    ]
    for payload in generated_clean:
        assert validate_payload(payload.encode()) == 0, f"Generated benign payload was rejected: {payload}"
    for payload in generated_evil:
        assert validate_payload(payload.encode()) == 1, f"Generated malicious payload bypassed the WAF: {payload}"


def test_proxy_auth_header_in_source():
    proxy_dir = "/app/proxy/"
    assert os.path.isdir(proxy_dir), f"Missing proxy directory at {proxy_dir}"
    found = False
    for f in os.listdir(proxy_dir):
        if f.endswith(".c") or f.endswith(".h"):
            with open(os.path.join(proxy_dir, f), "r", encoding="utf-8", errors="ignore") as fd:
                if "blackberry" in fd.read().lower():
                    found = True
                    break
    assert found, "The transcribed word 'blackberry' was not found in the proxy source code. Expected the header X-Proxy-Auth: blackberry to be injected."


def test_build_and_run_script_exists():
    script_path = "/app/build_and_run.sh"
    assert os.path.isfile(script_path), f"Missing deployment script at {script_path}"
    with open(script_path, "r", encoding="utf-8", errors="ignore") as fd:
        content = fd.read()
    assert "gcc" in content, "Deployment script does not contain a 'gcc' command to compile the proxy."
    assert "c-proxy" in content, "Deployment script does not compile to an executable named 'c-proxy'."
    assert "go run" in content or "go build" in content or "backend" in content, "Deployment script does not appear to start the Go backend."


def test_backend_builds_listens_and_is_race_free_under_requests():
    backend_bin = "/tmp/backend-race"
    result = subprocess.run(
        ["go", "build", "-race", "-o", backend_bin, "."],
        cwd="/app/backend",
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Go backend failed to compile with the race detector:\n{result.stderr}"

    proc = subprocess.Popen(
        [backend_bin], cwd="/app/backend", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        wait_port(8080, 12)
        responses = []
        failures = []

        def hit(i):
            try:
                response = raw_http(8080, f'{{"request":{i}}}'.encode(), f"/race-{i}")
                responses.append(response)
            except Exception as exc:
                failures.append(str(exc))

        threads = [threading.Thread(target=hit, args=(i,)) for i in range(32)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(5)
        assert not failures, f"Backend failed concurrent requests: {failures[:3]}"
        assert len(responses) == 32 and all(r.startswith(b"HTTP/") for r in responses), "Backend did not return valid HTTP responses to concurrent requests"
    finally:
        stop_group(proc)
    stderr = proc.stderr.read().decode(errors="replace") if proc.stderr else ""
    assert "DATA RACE" not in stderr, f"Go race detector reported a race:\n{stderr}"


def test_deployment_and_live_proxy_behavior():
    script = "/app/build_and_run.sh"
    os.chmod(script, os.stat(script).st_mode | 0o100)
    deployed = subprocess.Popen(
        ["bash", script], cwd="/app", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        wait_port(8080, 20)
        wait_port(8000, 20)
        response = raw_http(8000, b'{"username":"deployment_probe","age":25}', "/deployment-probe", 5)
        assert response.startswith(b"HTTP/"), "The deployed proxy did not return an HTTP response for a benign request"
        assert deployed.poll() is None, "build_and_run.sh exited instead of keeping the deployed services running"
    finally:
        stop_group(deployed)

    proxy_bin = "/app/c-proxy"
    assert os.path.isfile(proxy_bin), "build_and_run.sh did not produce /app/c-proxy"
    assert os.access(proxy_bin, os.X_OK), "/app/c-proxy is not executable"

    received = []
    event = threading.Event()

    class Recorder(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            received.append((dict(self.headers.items()), body, self.path))
            event.set()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"backend-ok")

        def log_message(self, fmt, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 8080), Recorder)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    proxy = subprocess.Popen([proxy_bin], cwd="/app", stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        wait_port(8000, 8)
        benign = f'{{"username":"live_{random.randrange(100000,999999)}","age":25}}'.encode()
        response = raw_http(8000, benign, "/header-probe", 5)
        assert response.startswith(b"HTTP/"), "Standalone c-proxy did not return an HTTP response"
        assert event.wait(3), "The proxy did not forward a benign request to the backend"
        headers, forwarded_body, forwarded_path = received[-1]
        auth_values = [v for k, v in headers.items() if k.lower() == "x-proxy-auth"]
        assert auth_values == ["blackberry"], f"Forwarded request had incorrect X-Proxy-Auth header: {auth_values}"
        assert forwarded_body == benign, "Proxy did not preserve the forwarded POST body"

        before = len(received)
        evil = f'{{"q":"x\' OR {random.randrange(10000,99999)}={random.randrange(10000,99999)} -- <script>alert(1)</script>"}}'.encode()
        try:
            raw_http(8000, evil, "/blocked-probe", 3)
        except OSError:
            pass
        time.sleep(0.5)
        assert len(received) == before, "The live proxy forwarded a malicious payload instead of blocking it"
        assert proxy.poll() is None, "c-proxy crashed while handling requests"
    finally:
        stop_group(proxy)
        server.shutdown()
        server.server_close()
        server_thread.join(3)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
