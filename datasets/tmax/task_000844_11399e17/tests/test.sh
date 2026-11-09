#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import pwd
import re
import secrets
import signal
import subprocess
import time

import pytest

BACKEND = "/home/user/backend/server"
BACKEND_DIR = "/home/user/backend"
CONFIG = "/home/user/nginx.conf"
USER = pwd.getpwnam("user")
backend_process = None


def as_user():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return result


def wait_for_listener(port, present=True, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if bool(pids) == present:
            return pids
        time.sleep(0.05)
    pytest.fail(f"Port {port} did not become {'listening' if present else 'closed'}")


def process_exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def process_uid(pid):
    return os.stat(f"/proc/{pid}").st_uid


def stop_backend():
    global backend_process
    for pid in list(listener_pids(8080)):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    wait_for_listener(8080, present=False)
    if backend_process is not None:
        try:
            backend_process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            backend_process.kill()
            backend_process.wait(timeout=2)
        backend_process = None


def start_backend():
    global backend_process
    backend_process = subprocess.Popen(
        [BACKEND], cwd=BACKEND_DIR, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        preexec_fn=as_user,
    )
    pids = wait_for_listener(8080, present=True)
    assert backend_process.pid in pids, "The newly compiled server did not open port 8080"
    assert process_uid(backend_process.pid) == USER.pw_uid, "Backend is not running as the default user"
    assert os.path.samefile(f"/proc/{backend_process.pid}/exe", BACKEND), "Port 8080 is not served by the compiled backend/server executable"


def source_ip():
    data = secrets.token_bytes(3)
    return f"127.{1 + data[0] % 253}.{1 + data[1] % 253}.{1 + data[2] % 253}"


def request(port, path, key=None, source=None):
    conn = http.client.HTTPConnection(
        "127.0.0.1", port, timeout=3,
        source_address=(source, 0) if source else None,
    )
    headers = {}
    if key is not None:
        headers["X-Utility-Key"] = key
    try:
        conn.request("GET", path, headers=headers)
        response = conn.getresponse()
        body = response.read()
        return response.status, body
    finally:
        conn.close()


def test_success_log_exists():
    assert os.path.isfile("/home/user/success.log"), "The file /home/user/success.log does not exist. Did you forget to create it?"


def test_server_built():
    global backend_process
    assert os.path.isfile(BACKEND), f"The server executable at {BACKEND} does not exist. Make sure the Makefile is fixed and make was run."
    assert os.access(BACKEND, os.X_OK), f"The file at {BACKEND} is not executable."
    assert open(BACKEND, "rb").read(4) == b"\x7fELF", "backend/server is not a compiled executable"

    original_pids = listener_pids(8080)
    assert original_pids, "The backend was not started on port 8080"
    assert any(process_uid(pid) == USER.pw_uid and os.path.samefile(f"/proc/{pid}/exe", BACKEND) for pid in original_pids), \
        "Port 8080 was not being served by /home/user/backend/server as the default user"

    build = subprocess.run(
        ["make", "clean", "all"], cwd=BACKEND_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
        preexec_fn=as_user,
    )
    assert build.returncode == 0, f"The repaired Makefile still fails when make is run:\n{build.stdout}"
    assert os.path.isfile(BACKEND) and os.access(BACKEND, os.X_OK), "make did not produce an executable server"
    assert open(BACKEND, "rb").read(4) == b"\x7fELF", "make did not compile an ELF server executable"
    assert os.path.isfile(f"{BACKEND_DIR}/server.o") and os.path.isfile(f"{BACKEND_DIR}/utils.o"), "make did not compile the project object files"

    stop_backend()
    start_backend()
    status, body = request(8080, "/direct-check")
    assert status == 200, f"The compiled backend on port 8080 returned {status}, not 200"
    assert b"Utility Backend Active" in body, "The compiled C backend returned an unexpected response"


def test_nginx_is_configured_and_running():
    pids = listener_pids(8000)
    assert pids, "Nothing is listening on port 8000"
    assert any(process_exe(pid) == "/usr/sbin/nginx" and process_uid(pid) == USER.pw_uid for pid in pids), \
        "Port 8000 is not served by Nginx running as the default user"

    configured_master = False
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            cmdline = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
            if "nginx" in cmdline and "-c" in cmdline and CONFIG in cmdline and process_uid(int(entry)) == USER.pw_uid:
                configured_master = True
                break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert configured_master, "Nginx was not started as user with nginx -c /home/user/nginx.conf"

    checked = subprocess.run(
        ["/usr/sbin/nginx", "-T", "-c", CONFIG], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10,
        preexec_fn=as_user,
    )
    assert checked.returncode == 0, f"The modified Nginx configuration is invalid:\n{checked.stdout}"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:8080/\s*;", checked.stdout), \
        "The /api/ proxy is not configured to use http://127.0.0.1:8080/"


def test_nginx_invalid_header():
    # Taking the backend down proves invalid requests are rejected by Nginx and
    # that valid requests really depend on the backend rather than a fake 200 response.
    stop_backend()
    try:
        status, _ = request(8000, f"/api/{secrets.token_hex(8)}", source=source_ip())
        assert status == 403, f"Expected 403 Forbidden for missing X-Utility-Key header, but got {status}."

        wrong_key = "wrong-" + secrets.token_hex(12)
        status, _ = request(8000, f"/api/{secrets.token_hex(8)}", key=wrong_key, source=source_ip())
        assert status == 403, f"Expected 403 Forbidden for an incorrect nonempty X-Utility-Key, but got {status}."

        status, _ = request(8000, f"/api/{secrets.token_hex(8)}", key="secret123", source=source_ip())
        assert status == 502, f"A valid request returned {status} with the backend stopped; it is not being proxied to port 8080"
    finally:
        start_backend()


def test_nginx_valid_request_and_rate_limit():
    client_a = source_ip()
    client_b = source_ip()
    path = f"/api/{secrets.token_hex(10)}"

    time.sleep(1.1)
    status, body = request(8000, path, key="secret123", source=client_a)
    assert status == 200, f"Expected 200 OK for valid request, but got {status}."
    assert b"Utility Backend Active" in body, "The valid request did not return the C backend response"

    status, _ = request(8000, path, key="secret123", source=client_a)
    assert status == 503, f"Expected 503 Service Unavailable for an immediate excess request, but got {status}."

    status, body = request(8000, path, key="secret123", source=client_b)
    assert status == 200, f"A different client IP was incorrectly rate-limited; got {status}."
    assert b"Utility Backend Active" in body
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
