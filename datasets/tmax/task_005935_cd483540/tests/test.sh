#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

import pytest


def get_expected_plaintext():
    v1_path = "/home/user/v1.txt"
    v2_path = "/home/user/v2.txt"

    with open(v1_path, "r") as f:
        v1_lines = set(line.strip() for line in f if line.strip())

    with open(v2_path, "r") as f:
        v2_lines = [line.strip() for line in f if line.strip()]

    new_lines = [line for line in v2_lines if line not in v1_lines]
    new_lines.sort()
    return "\n".join(new_lines)


def request_status(url, auth=None):
    req = urllib.request.Request(url)
    if auth is not None:
        req.add_header("X-Release-Auth", auth)
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")


def listening_socket_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table, "r") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) < 10 or fields[3] != "0A":
                    continue
                if int(fields[1].rsplit(":", 1)[1], 16) == port:
                    inodes.add(fields[9])
    return inodes


def processes_owning_port(port):
    wanted = listening_socket_inodes(port)
    owners = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            owns_socket = any(
                os.readlink(os.path.join(fd_dir, fd)) in {f"socket:[{inode}]" for inode in wanted}
                for fd in os.listdir(fd_dir)
            )
            if not owns_socket:
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
            exe = os.path.realpath(f"/proc/{pid}/exe")
            cwd = os.path.realpath(f"/proc/{pid}/cwd")
            owners.append((int(pid), exe, argv, cwd))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def process_runs_script(proc, expected):
    _, exe, argv, cwd = proc
    if not os.path.basename(exe).startswith("python"):
        return False
    expected = os.path.realpath(expected)
    for arg in argv[1:]:
        if arg.startswith("-"):
            continue
        candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
        if os.path.realpath(candidate) == expected:
            return True
    return False


def test_release_diff_b64_content():
    path = "/home/user/release_diff.b64"
    assert os.path.exists(path), f"File {path} does not exist."

    expected_plaintext = get_expected_plaintext()
    expected_b64 = base64.b64encode(expected_plaintext.encode("utf-8")).decode("utf-8")

    with open(path, "r") as f:
        actual_b64 = f.read().strip()

    assert actual_b64 == expected_b64, "The base64 content in release_diff.b64 does not match the expected output."


def test_required_artifacts_exist_and_server_uses_stdlib():
    for path in ("/home/user/server.py", "/home/user/nginx.conf"):
        assert os.path.isfile(path), f"Required artifact {path} is missing or is not a regular file."

    with open("/home/user/server.py", "r") as f:
        tree = ast.parse(f.read(), filename="/home/user/server.py")
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])
    non_stdlib = sorted(name for name in imported if name not in sys.stdlib_module_names)
    assert not non_stdlib, f"server.py imports non-standard-library modules: {non_stdlib}"


def test_backend_is_running_on_9000_and_executes_server_py():
    owners = processes_owning_port(9000)
    assert owners, "Nothing is listening on port 9000."
    assert any(process_runs_script(proc, "/home/user/server.py") for proc in owners), \
        "Port 9000 is not owned by a Python process running /home/user/server.py."


def test_backend_direct_behavior():
    status, _ = request_status("http://127.0.0.1:9000/direct-check")
    assert status == 403, f"Backend should return 403 without authentication, got {status}."

    status, _ = request_status("http://127.0.0.1:9000/direct-check", "wrong")
    assert status == 403, f"Backend should return 403 for incorrect authentication, got {status}."

    status, body = request_status("http://127.0.0.1:9000/any-get-path", "YXBwcm92ZWQ=")
    assert status == 200, f"Backend should return 200 for correct authentication, got {status}."
    assert body.strip() == get_expected_plaintext(), "Backend did not decode and return the expected release notes."


def test_nginx_configuration_and_listener():
    result = subprocess.run(
        ["nginx", "-T", "-c", "/home/user/nginx.conf"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"nginx.conf is not a valid Nginx configuration:\n{result.stdout}"

    config = "\n".join(line.split("#", 1)[0] for line in result.stdout.splitlines())
    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\s*;", config), "Nginx must listen on 127.0.0.1:8080."
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:9000\s*;", config), "Nginx must proxy to 127.0.0.1:9000."
    zones = re.findall(
        r"\blimit_req_zone\s+\$binary_remote_addr\s+zone=([A-Za-z0-9_]+):[^;\s]+\s+rate=30r/m\s*;",
        config,
    )
    assert zones, "Nginx must define a 30 requests/minute limit_req_zone based on $binary_remote_addr."
    assert any(re.search(rf"\blimit_req\s+zone={re.escape(zone)}\s+burst=5\s+nodelay\s*;", config) for zone in zones), \
        "Nginx must apply the rate-limit zone with burst=5 and nodelay."

    owners = processes_owning_port(8080)
    assert owners, "Nothing is listening on port 8080."
    nginx_owners = [proc for proc in owners if os.path.basename(proc[1]) == "nginx"]
    assert nginx_owners, "Port 8080 is not owned by Nginx."
    assert any("/home/user/nginx.conf" in proc[2] for proc in nginx_owners), \
        "The Nginx process on port 8080 was not started with /home/user/nginx.conf."


def test_nginx_proxy_forbidden_without_auth():
    req = urllib.request.Request("http://127.0.0.1:8080/")
    try:
        urllib.request.urlopen(req)
        pytest.fail("Expected HTTP Error 403, but request succeeded.")
    except urllib.error.HTTPError as e:
        assert e.code == 403, f"Expected HTTP 403 Forbidden, got {e.code}"


def test_nginx_proxy_success_with_auth():
    req = urllib.request.Request("http://127.0.0.1:8080/")
    req.add_header("X-Release-Auth", "YXBwcm92ZWQ=")

    try:
        with urllib.request.urlopen(req) as response:
            assert response.status == 200, f"Expected HTTP 200 OK, got {response.status}"
            content = response.read().decode("utf-8").strip()
            expected_plaintext = get_expected_plaintext()
            assert content == expected_plaintext, "The decoded plaintext from the server does not match the expected output."
    except urllib.error.HTTPError as e:
        pytest.fail(f"Expected HTTP 200 OK, but got HTTPError {e.code}")


def test_nginx_rate_limiting():
    # Rate limit is 30 req/min, burst 5. Sending ~10 rapid requests should trigger a 503.
    req = urllib.request.Request("http://127.0.0.1:8080/")
    req.add_header("X-Release-Auth", "YXBwcm92ZWQ=")

    status_codes = []
    for _ in range(15):
        try:
            with urllib.request.urlopen(req) as response:
                status_codes.append(response.status)
        except urllib.error.HTTPError as e:
            status_codes.append(e.code)

    assert 503 in status_codes, "Expected HTTP 503 Service Unavailable due to rate limiting, but it was not triggered."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
