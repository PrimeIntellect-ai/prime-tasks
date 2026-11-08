#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import os
import random
import secrets
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest


class MockBackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        token = self.headers.get("X-Verifier-Token", "")
        self.server.seen.append((self.path, token))
        body = ("BACKEND_OK\nPATH=" + self.path + "\nTOKEN=" + token).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


@pytest.fixture(scope="module")
def mock_backend():
    server = HTTPServer(("127.0.0.1", 9000), MockBackendHandler)
    server.seen = []
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield server
    server.shutdown()
    server.server_close()


def test_detect_script_adversarial_corpus():
    script_path = "/home/user/detect.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    evil_dir = "/home/user/corpora/evil/"
    clean_dir = "/home/user/corpora/clean/"

    evil_files = glob.glob(os.path.join(evil_dir, "*"))
    clean_files = glob.glob(os.path.join(clean_dir, "*"))

    assert len(evil_files) > 0, "No evil files found to test."
    assert len(clean_files) > 0, "No clean files found to test."

    evil_bypassed = []
    for e_file in evil_files:
        result = subprocess.run([script_path, e_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(e_file))

    clean_modified = []
    for c_file in clean_files:
        result = subprocess.run([script_path, c_file], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(c_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not errors, "Adversarial corpus failed:\n" + "\n".join(errors)


def expected_detector_status(payload):
    blocks = [payload[i:i + 16] for i in range(0, len(payload) - 15, 16)]
    return 1 if len(blocks) != len(set(blocks)) else 0


def test_detect_script_randomized_content_and_paths():
    script_path = "/home/user/detect.sh"
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix="session-verifier-") as root:
        cases = []

        for _ in range(10):
            count = rng.randint(1, 9)
            blocks = []
            while len(blocks) < count:
                block = secrets.token_bytes(16)
                if block not in blocks:
                    blocks.append(block)
            payload = b"".join(blocks) + secrets.token_bytes(rng.randint(0, 15))
            cases.append(payload)

        for _ in range(10):
            count = rng.randint(2, 9)
            blocks = []
            while len(blocks) < count:
                block = secrets.token_bytes(16)
                if block not in blocks:
                    blocks.append(block)
            source = rng.randrange(len(blocks))
            insertion = rng.randrange(len(blocks) + 1)
            blocks.insert(insertion, blocks[source])
            payload = b"".join(blocks) + secrets.token_bytes(rng.randint(0, 15))
            cases.append(payload)

        rng.shuffle(cases)
        for payload in cases:
            nested = os.path.join(root, secrets.token_hex(8), secrets.token_hex(6))
            os.makedirs(nested)
            path = os.path.join(nested, secrets.token_hex(12) + ".dat")
            with open(path, "wb") as handle:
                handle.write(base64.b64encode(payload) + b"\n")

            expected = expected_detector_status(payload)
            try:
                result = subprocess.run(
                    [script_path, path], capture_output=True, timeout=5
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Detector timed out on randomized input {path}")
            assert result.returncode == expected, (
                f"Detector returned {result.returncode}, expected {expected}, "
                f"for a randomized payload of {len(payload)} bytes"
            )


def listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(inode)
        except FileNotFoundError:
            pass
    return result


def process_info(pid):
    try:
        exe = os.path.realpath(f"/proc/{pid}/exe")
        with open(f"/proc/{pid}/cmdline", "rb") as handle:
            cmd = handle.read().replace(b"\0", b" ").decode(errors="replace")
        with open(f"/proc/{pid}/status") as handle:
            status = handle.read().splitlines()
        ppid = int(next(line.split()[1] for line in status if line.startswith("PPid:")))
        return exe, cmd, ppid
    except (FileNotFoundError, ProcessLookupError, PermissionError, StopIteration):
        return None


def socket_owner_pids(inodes):
    owners = set()
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for proc_path in glob.glob("/proc/[0-9]*"):
        pid = int(os.path.basename(proc_path))
        try:
            for fd in os.scandir(os.path.join(proc_path, "fd")):
                try:
                    if os.readlink(fd.path) in wanted:
                        owners.add(pid)
                        break
                except (FileNotFoundError, PermissionError):
                    continue
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def has_custom_nginx_ancestor(pid):
    visited = set()
    while pid > 1 and pid not in visited:
        visited.add(pid)
        info = process_info(pid)
        if info is None:
            return False
        exe, cmd, ppid = info
        if exe == os.path.realpath("/usr/sbin/nginx") and "/home/user/nginx/nginx.conf" in cmd and "-c" in cmd:
            return True
        pid = ppid
    return False


def test_real_nginx_uses_custom_configuration():
    config = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(config), f"Nginx configuration {config} does not exist."

    syntax = subprocess.run(
        ["/usr/sbin/nginx", "-t", "-c", config], capture_output=True, text=True
    )
    assert syntax.returncode == 0, "Custom Nginx configuration is invalid:\n" + syntax.stderr

    deadline = time.time() + 5
    owners = set()
    while time.time() < deadline:
        inodes = listening_inodes(8080)
        owners = socket_owner_pids(inodes)
        if owners:
            break
        time.sleep(0.1)

    assert owners, "No process is listening on port 8080."
    nginx_owners = []
    for pid in owners:
        info = process_info(pid)
        if info and info[0] == os.path.realpath("/usr/sbin/nginx"):
            nginx_owners.append(pid)

    assert nginx_owners, "Port 8080 is not being served by the installed Nginx executable."
    assert any(has_custom_nginx_ancestor(pid) for pid in nginx_owners), (
        "The Nginx process serving port 8080 was not started with "
        "-c /home/user/nginx/nginx.conf."
    )


def test_nginx_routing_and_filtering(mock_backend):
    time.sleep(1)

    req = urllib.request.Request("http://127.0.0.1:8080/api/test")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected 200 OK, got {response.status}"
            body = response.read()
            assert b"BACKEND_OK" in body, "Response did not come from the mock backend."
    except urllib.error.HTTPError as e:
        pytest.fail(f"Normal request to /api/test failed with HTTP error: {e.code}")
    except Exception as e:
        pytest.fail(f"Normal request to /api/test failed: {e}")

    assert any(path == "/api/test" for path, _ in mock_backend.seen), (
        "The normal request was not received by the backend."
    )

    before_bypass = len(mock_backend.seen)
    req_bypass = urllib.request.Request("http://127.0.0.1:8080/api/test")
    req_bypass.add_header("X-Debug-Bypass", "true")
    try:
        with urllib.request.urlopen(req_bypass, timeout=5) as response:
            pytest.fail(f"Expected 403 Forbidden for bypass header, but got {response.status}")
    except urllib.error.HTTPError as e:
        assert e.code == 403, f"Expected 403 Forbidden for bypass header, got {e.code}"
    except Exception as e:
        pytest.fail(f"Bypass request failed with unexpected error: {e}")
    assert len(mock_backend.seen) == before_bypass, "Blocked request was forwarded to the backend."

    for _ in range(6):
        path = "/api/" + secrets.token_urlsafe(12) + "?q=" + secrets.token_hex(7)
        token = secrets.token_hex(20)
        req = urllib.request.Request("http://127.0.0.1:8080" + path)
        req.add_header("X-Verifier-Token", token)
        with urllib.request.urlopen(req, timeout=5) as response:
            body = response.read().decode(errors="replace")
            assert response.status == 200
            assert "PATH=" + path in body
            assert "TOKEN=" + token in body
        assert (path, token) in mock_backend.seen, "Randomized request did not reach the backend."

        blocked_before = len(mock_backend.seen)
        blocked = urllib.request.Request("http://127.0.0.1:8080" + path)
        blocked.add_header("X-Verifier-Token", token)
        blocked.add_header("X-Debug-Bypass", "true")
        with pytest.raises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(blocked, timeout=5)
        assert error.value.code == 403
        assert len(mock_backend.seen) == blocked_before, "A randomized blocked request reached the backend."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
