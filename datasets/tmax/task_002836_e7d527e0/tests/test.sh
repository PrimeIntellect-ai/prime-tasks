#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest


def run_sanitizer(sanitizer_bin, path):
    return subprocess.run([sanitizer_bin, path], capture_output=True, timeout=5).returncode


def test_sanitizer_adversarial_corpus():
    sanitizer_bin = "/home/user/sanitizer"
    assert os.path.isfile(sanitizer_bin), f"Sanitizer binary not found at {sanitizer_bin}"
    assert os.access(sanitizer_bin, os.X_OK), f"Sanitizer binary is not executable"

    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No evil files found in corpus."
    assert len(clean_files) > 0, "No clean files found in corpus."

    evil_bypassed = []
    for f in evil_files:
        result = subprocess.run([sanitizer_bin, f], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(f))

    clean_modified = []
    for f in clean_files:
        result = subprocess.run([sanitizer_bin, f], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not errors, " | ".join(errors)


def test_sanitizer_generated_payloads():
    sanitizer_bin = "/home/user/sanitizer"
    assert os.path.isfile(sanitizer_bin), f"Sanitizer binary not found at {sanitizer_bin}"
    assert os.access(sanitizer_bin, os.X_OK), f"Sanitizer binary is not executable"

    cases = [
        ("diff", 0, "--- a/src/widget.cpp\n+++ b/src/widget.cpp\n@@ -1 +1 @@\n-old\n+new\n"),
        ("asm", 0, "mov eax, 1\nadd eax, 2\nret\n"),
        ("diff", 1, "--- a/../../etc/passwd\n+++ b/../../etc/passwd\n@@ -1 +1 @@\n-old\n+new\n"),
        ("diff", 1, "--- /etc/passwd\n+++ /etc/passwd\n@@ -1 +1 @@\n-old\n+new\n"),
        ("asm", 1, "mov rax, execve\n"),
        ("asm", 1, "mov eax, 59\nsyscall\n"),
        ("asm", 1, "xor eax, eax\nint 0x80\n"),
    ]

    with tempfile.TemporaryDirectory(prefix="sanitizer-check-") as tmpdir:
        failures = []
        for extension, expected, payload in cases:
            path = os.path.join(tmpdir, f"{uuid.uuid4().hex}.{extension}")
            with open(path, "w", encoding="utf-8") as f:
                f.write(payload)
            actual = run_sanitizer(sanitizer_bin, path)
            if actual != expected:
                failures.append(f"{os.path.basename(path)} expected {expected}, got {actual}")
        assert not failures, " | ".join(failures)


def test_nginx_routing_config():
    nginx_conf = "/app/nginx/nginx.conf"
    assert os.path.isfile(nginx_conf), f"Nginx configuration not found at {nginx_conf}"

    with open(nginx_conf, "r") as f:
        conf = f.read()

    assert "proxy_pass" in conf, "Nginx config missing proxy_pass directives."
    assert "9001" in conf, "Nginx config missing routing to port 9001 (Storage Backend)."
    assert "9002" in conf, "Nginx config missing routing to port 9002 (Execution Backend)."


def test_nginx_services_running_and_routing():
    try:
        req_patch = urllib.request.urlopen("http://localhost:8080/api/patch", timeout=5)
        patch_code = req_patch.getcode()
    except urllib.error.HTTPError as e:
        patch_code = e.code
    except Exception as e:
        pytest.fail(f"Failed to connect to /api/patch via Nginx. Are the services running? Error: {e}")

    try:
        req_asm = urllib.request.urlopen("http://localhost:8080/api/asm", timeout=5)
        asm_code = req_asm.getcode()
    except urllib.error.HTTPError as e:
        asm_code = e.code
    except Exception as e:
        pytest.fail(f"Failed to connect to /api/asm via Nginx. Are the services running? Error: {e}")

    assert patch_code != 502, "/api/patch returned 502 Bad Gateway, meaning proxy_pass failed to reach port 9001."
    assert asm_code != 502, "/api/asm returned 502 Bad Gateway, meaning proxy_pass failed to reach port 9002."


def listener_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def stop_listeners(port):
    inodes = listener_inodes(port)
    if not inodes:
        return
    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_inodes(port):
        time.sleep(0.05)
    if listener_inodes(port):
        for pid in victims:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.1)


def wait_for_port(port, process):
    deadline = time.time() + 5
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"Distinct test backend on port {port} exited early")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail(f"Distinct test backend on port {port} did not start")


def test_nginx_routes_each_endpoint_to_the_specified_backend():
    stop_listeners(9001)
    stop_listeners(9002)

    patch_token = "storage-" + uuid.uuid4().hex
    asm_token = "execution-" + uuid.uuid4().hex
    server_code = r'''
import http.server
import sys

port = int(sys.argv[1])
token = sys.argv[2].encode("ascii")

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(token)))
        self.end_headers()
        self.wfile.write(token)
    def log_message(self, *args):
        pass

http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
'''

    processes = [
        subprocess.Popen(["python3", "-c", server_code, "9001", patch_token]),
        subprocess.Popen(["python3", "-c", server_code, "9002", asm_token]),
    ]
    try:
        wait_for_port(9001, processes[0])
        wait_for_port(9002, processes[1])

        nonce = uuid.uuid4().hex
        with urllib.request.urlopen(f"http://localhost:8080/api/patch?check={nonce}", timeout=5) as response:
            patch_body = response.read().decode("ascii")
        with urllib.request.urlopen(f"http://localhost:8080/api/asm?check={nonce}", timeout=5) as response:
            asm_body = response.read().decode("ascii")

        assert patch_body == patch_token, "/api/patch did not reach the Storage Backend on port 9001"
        assert asm_body == asm_token, "/api/asm did not reach the Execution Backend on port 9002"
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
        for process in processes:
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
