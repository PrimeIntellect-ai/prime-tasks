#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import threading
import pytest
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = "/home/user/waf-proxy"
BINARY = os.path.join(ROOT, "static-waf")
PROXY_PID = None


def kill_listeners(port):
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) in (1, os.getpid()):
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            import socket
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Port {port} did not become ready")


def test_sanitizer_fixed():
    path = os.path.join(ROOT, "sanitizer.c")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "max_len" in content, "sanitizer.c does not seem to use max_len to prevent buffer overflow."

    harness = r'''
#include <stdio.h>
#include <string.h>
#include "sanitizer.h"

int main(void) {
    static const int limits[] = {-1, 0, 1, 2, 7, 16, 63, 64, 65, 127, 240};
    char input[256];
    unsigned char output[512];

    for (int len = 0; len <= 220; len++) {
        for (int i = 0; i < len; i++) input[i] = (char)('a' + ((i * 17 + len) % 26));
        input[len] = '\0';

        for (unsigned k = 0; k < sizeof(limits) / sizeof(limits[0]); k++) {
            int max_len = limits[k];
            memset(output, 0xA5, sizeof(output));
            unsigned char *dest = output + 128;
            sanitize_header(input, (char *)dest, max_len);

            int copied = 0;
            if (max_len > 0) copied = len < max_len - 1 ? len : max_len - 1;

            for (int i = 0; i < 512; i++) {
                unsigned char expected = 0xA5;
                int relative = i - 128;
                if (max_len > 0 && relative >= 0 && relative < copied)
                    expected = (unsigned char)input[relative];
                else if (max_len > 0 && relative == copied)
                    expected = 0;
                if (output[i] != expected) {
                    fprintf(stderr, "bad write: input_len=%d max_len=%d offset=%d got=%u expected=%u\n",
                            len, max_len, relative, output[i], expected);
                    return 1;
                }
            }
        }
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "sanitizer_test.c")
        executable = os.path.join(td, "sanitizer_test")
        with open(harness_path, "w") as f:
            f.write(harness)
        subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", "-I", ROOT,
             harness_path, path, "-o", executable],
            check=True, timeout=30
        )
        subprocess.run([executable], check=True, timeout=30)


def test_build_script_exists():
    path = os.path.join(ROOT, "build.sh")
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_run_script_exists():
    path = os.path.join(ROOT, "run.sh")
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_build_script_actually_builds_binary():
    kill_listeners(8080)
    try:
        os.unlink(BINARY)
    except FileNotFoundError:
        pass

    subprocess.run(
        [os.path.join(ROOT, "build.sh")], cwd=ROOT,
        check=True, timeout=300
    )
    assert os.path.isfile(BINARY), f"Binary {BINARY} was not built by build.sh."
    assert os.access(BINARY, os.X_OK), "static-waf is not executable."

    file_output = subprocess.check_output(["file", BINARY], text=True)
    assert "ELF" in file_output and "executable" in file_output, file_output

    metadata = subprocess.check_output(["go", "version", "-m", BINARY],
                                       stderr=subprocess.STDOUT, text=True)
    assert "path\twaf-proxy" in metadata, "static-waf was not built as the supplied Go application."


def test_statically_linked_binary():
    assert os.path.isfile(BINARY), f"Binary {BINARY} was not built."
    try:
        output = subprocess.check_output(["ldd", BINARY], stderr=subprocess.STDOUT).decode("utf-8")
        assert "not a dynamic executable" in output, "Binary is not statically linked (ldd output indicates dynamic dependencies)."
    except subprocess.CalledProcessError as e:
        output = e.output.decode("utf-8")
        assert "not a dynamic executable" in output, "Binary is not statically linked."


def test_run_script_starts_built_binary():
    global PROXY_PID
    kill_listeners(8080)
    pid_file = os.path.join(ROOT, "proxy.pid")
    try:
        os.unlink(pid_file)
    except FileNotFoundError:
        pass

    pids_before = {int(p) for p in os.listdir("/proc") if p.isdigit()}
    subprocess.run([os.path.join(ROOT, "run.sh")], cwd=ROOT, check=True, timeout=20)

    deadline = time.time() + 10
    while time.time() < deadline and not os.path.isfile(pid_file):
        time.sleep(0.1)
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."
    with open(pid_file) as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), "PID file does not contain a valid numeric PID."
    pid = int(pid_str)
    assert pid not in pids_before, "run.sh did not start a new process."

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running.")

    exe_path = f"/proc/{pid}/exe"
    assert os.path.exists(exe_path), "PID does not identify a running executable."
    assert os.path.samefile(exe_path, BINARY), "proxy.pid does not identify the built static-waf binary."
    PROXY_PID = pid
    wait_for_port(8080)


def test_proxy_running_and_pid_file():
    pid_file = os.path.join(ROOT, "proxy.pid")
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), "PID file does not contain a valid numeric PID."
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running.")


class MockBackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        user = self.headers.get("X-Custom-User", "")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(user.encode("utf-8"))

    def log_message(self, format, *args):
        pass


def request_with_header(value):
    req = urllib.request.Request("http://127.0.0.1:8080/")
    req.add_header("X-Custom-User", value)
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.read().decode("utf-8")


def test_proxy_truncation_behavior():
    global PROXY_PID
    kill_listeners(9090)
    server = HTTPServer(("127.0.0.1", 9090), MockBackendHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        assert request_with_header("alice") == "alice"

        overflow_payload = "A" * 100
        expected_trunc = "A" * 63
        body = request_with_header(overflow_payload)
        assert body == expected_trunc, f"Expected truncated payload of length 63, got length {len(body)}"

        rng = random.Random(secrets.randbits(128))
        alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        lengths = [1, 62, 63, 64, 65, 127, 255]
        lengths += [rng.randint(2, 2000) for _ in range(12)]
        for length in lengths:
            value = "".join(rng.choice(alphabet) for _ in range(length))
            expected = value[:63]
            body = request_with_header(value)
            assert body == expected, f"Incorrect sanitization for generated header length {length}"

        assert PROXY_PID is not None
        os.kill(PROXY_PID, 0)
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to proxy or proxy returned error: {e}")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
        if PROXY_PID is not None:
            try:
                os.kill(PROXY_PID, signal.SIGTERM)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
