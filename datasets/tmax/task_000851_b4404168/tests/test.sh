#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import pwd
import secrets
import socket
import stat
import subprocess
import time

import pytest

BASE = "/home/user/deployment_test"
BACKEND = os.path.join(BASE, "backend")
SOURCE = os.path.join(BASE, "backend.c")
CONF = os.path.join(BASE, "nginx.conf")
COMPILED_SOURCE = "/tmp/backend_from_source"


def demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def cleanup_services():
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-x", "backend"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.25)


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def wait_for_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for port {port}")


def request_status(port, path, version=None):
    headers = {}
    if version is not None:
        headers["X-API-Version"] = version
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
    try:
        conn.request("GET", path, headers=headers)
        response = conn.getresponse()
        response.read()
        return response.status
    finally:
        conn.close()


def semantic_cases():
    cases = [(2, 2, 0), (2, 1, secrets.randbelow(90) + 10)]
    cases.append((2, secrets.randbelow(20) + 10, secrets.randbelow(100)))
    cases.append((secrets.randbelow(6) + 3, secrets.randbelow(30), secrets.randbelow(30)))
    cases.append((secrets.randbelow(2), secrets.randbelow(30), secrets.randbelow(30)))
    return [(".".join(map(str, value)), 200 if value >= (2, 2, 0) else 426)
            for value in cases]


def start_backend(path):
    proc = subprocess.Popen([path], cwd=BASE, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, preexec_fn=demote_to_user)
    wait_for_port(9090)
    return proc


def assert_backend_semantics(path):
    proc = start_backend(path)
    try:
        for version, expected in semantic_cases():
            assert request_status(9090, "/probe", version) == expected, (
                f"Backend {path} returned the wrong status for semantic version {version}"
            )
    finally:
        stop_process(proc)
        time.sleep(0.2)


def test_results_log():
    log_path = os.path.join(BASE, "results.log")
    assert os.path.isfile(log_path), f"File {log_path} is missing. Did you run test.sh and redirect output?"
    with open(log_path, "r") as f:
        content = f.read().strip().split()
    expected = ["200", "426", "200", "200"]
    assert content == expected, f"Expected results.log to contain {expected}, but got {content}. This indicates either the backend logic or the nginx routing is incorrect."


def test_backend_c_fixed():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "strcmp(version, min_version)" not in content, "backend.c still contains the buggy strcmp implementation for check_version."


def test_nginx_conf_exists_and_valid():
    assert os.path.isfile(CONF), f"File {CONF} is missing. Did you create the Nginx configuration?"
    with open(CONF, "r") as f:
        content = f.read()
    assert "8080" in content, "nginx.conf does not seem to listen on port 8080."
    assert "X-API-Version" in content, "nginx.conf does not seem to set the X-API-Version header."
    assert "9090" in content, "nginx.conf does not seem to proxy to the backend port 9090."


def test_compiled_backend_and_functional_proxy():
    assert os.path.isfile(BACKEND), "The recompiled backend executable is missing."
    mode = os.stat(BACKEND).st_mode
    assert stat.S_ISREG(mode) and os.access(BACKEND, os.X_OK), "backend is not an executable regular file."
    with open(BACKEND, "rb") as f:
        assert f.read(4) == b"\x7fELF", "backend is not a compiled ELF executable."

    compile_result = subprocess.run(
        ["gcc", "-o", COMPILED_SOURCE, SOURCE], cwd=BASE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert compile_result.returncode == 0, f"backend.c does not compile: {compile_result.stderr}"

    cleanup_services()
    assert_backend_semantics(BACKEND)
    assert_backend_semantics(COMPILED_SOURCE)

    backend_proc = None
    nginx_proc = None
    capture_proc = None
    try:
        backend_proc = start_backend(BACKEND)
        nginx_proc = subprocess.Popen(
            ["nginx", "-c", CONF], cwd=BASE, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, preexec_fn=demote_to_user
        )
        wait_for_port(8080)

        for version, expected in semantic_cases():
            endpoint = "deploy" + secrets.token_hex(5)
            status = request_status(8080, f"/api/{version}/{endpoint}")
            assert status == expected, (
                f"Proxy returned {status}, expected {expected}, for version {version}"
            )

        stop_process(backend_proc)
        backend_proc = None
        time.sleep(0.25)

        version = f"{secrets.randbelow(7)+3}.{secrets.randbelow(50)}.{secrets.randbelow(50)}"
        endpoint = "endpoint" + secrets.token_hex(8)
        capture_script = "/tmp/capture_backend.py"
        with open(capture_script, "w") as f:
            f.write(r'''import os
import socket
expected_path = os.environ["EXPECTED_PATH"]
expected_version = os.environ["EXPECTED_VERSION"]
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 9090))
s.listen(10)
while True:
    conn, _ = s.accept()
    data = b""
    while b"\r\n\r\n" not in data and len(data) < 65536:
        part = conn.recv(4096)
        if not part:
            break
        data += part
    text = data.decode("latin1", "replace")
    lines = text.split("\r\n")
    path_ok = bool(lines) and len(lines[0].split()) >= 2 and lines[0].split()[1] == expected_path
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    header_ok = headers.get("x-api-version") == expected_version
    code = 211 if path_ok and header_ok else 418
    reason = "Routing OK" if code == 211 else "Routing Wrong"
    response = f"HTTP/1.1 {code} {reason}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    conn.sendall(response.encode("ascii"))
    conn.close()
''')
        env = os.environ.copy()
        env["EXPECTED_PATH"] = "/" + endpoint
        env["EXPECTED_VERSION"] = version
        capture_proc = subprocess.Popen(
            ["python3", capture_script], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, env=env, preexec_fn=demote_to_user
        )
        wait_for_port(9090)
        status = request_status(8080, f"/api/{version}/{endpoint}")
        assert status == 211, (
            "Nginx did not strip /api/<version>, preserve the endpoint, and pass "
            "the extracted version in X-API-Version to port 9090."
        )
    finally:
        stop_process(backend_proc)
        stop_process(capture_proc)
        cleanup_services()
        stop_process(nginx_proc)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
