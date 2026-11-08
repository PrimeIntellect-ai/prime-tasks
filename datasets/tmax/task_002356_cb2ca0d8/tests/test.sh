#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import signal
import socket
import struct
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

AMD64_PATH = "/home/user/app/go-auth/build/auth-amd64"
ARM64_PATH = "/home/user/app/go-auth/build/auth-arm64"
DETECTOR_PATH = "/home/user/detector.sh"
START_SCRIPT = "/home/user/start_services.sh"
NGINX_CONF = "/home/user/app/nginx/nginx.conf"
FLASK_APP = "/home/user/app/flask/app.py"


def elf_machine(path):
    with open(path, "rb") as f:
        header = f.read(64)
    assert header[:4] == b"\x7fELF", f"Not an ELF executable: {path}"
    assert header[4] == 2, f"Expected a 64-bit ELF executable: {path}"
    assert header[5] == 1, f"Expected a little-endian ELF executable: {path}"
    return struct.unpack("<H", header[18:20])[0]


def assert_go_binary(path, arch, machine):
    assert os.path.isfile(path), f"Missing Go binary: {path}"
    assert os.access(path, os.X_OK), f"Binary is not executable: {path}"
    assert elf_machine(path) == machine, f"Wrong architecture for {path}"

    info = subprocess.run(
        ["go", "version", "-m", path], capture_output=True, text=True, timeout=10
    )
    assert info.returncode == 0, f"Not a valid Go executable: {path}: {info.stderr}"
    assert "path\tauth" in info.stdout, f"Unexpected Go main module in {path}"
    assert f"GOARCH={arch}" in info.stdout, f"Go build metadata has wrong architecture in {path}"
    assert "GOOS=linux" in info.stdout, f"Go build metadata has wrong OS in {path}"

    with open(path, "rb") as f:
        data = f.read()
    assert b"/auth/login" in data, f"Go auth route is missing from {path}"
    assert b"authenticated" in data, f"Go auth response is missing from {path}"


def test_go_binaries_exist():
    assert_go_binary(AMD64_PATH, "amd64", 62)
    assert_go_binary(ARM64_PATH, "arm64", 183)


def run_detector(path):
    try:
        return subprocess.run(
            [DETECTOR_PATH, path], capture_output=True, timeout=5
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {path}")


def make_request(uri, version=None, extra_headers=None):
    lines = [f"GET {uri} HTTP/1.1", "Host: verifier.invalid"]
    if version is not None:
        lines.append(f"X-API-Version: {version}")
    if extra_headers:
        lines.extend(extra_headers)
    return "\n".join(lines) + "\n\n"


def test_detector_script_against_corpus_and_generated_requests():
    assert os.path.isfile(DETECTOR_PATH), f"Missing detector script: {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector script is not executable: {DETECTOR_PATH}"

    clean_dir = "/home/user/corpus/clean"
    evil_dir = "/home/user/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = [os.path.basename(p) for p in clean_files if run_detector(p) != 0]
    evil_failed = [os.path.basename(p) for p in evil_files if run_detector(p) != 1]
    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed)}")
    assert not error_messages, " | ".join(error_messages)

    cases = []
    token = secrets.token_hex(8)

    # Answers are derived from newly generated semantic-version tuples rather
    # than from any filename or preinstalled corpus path.
    for _ in range(12):
        major = random.randint(1, 8)
        minor = random.randint(0, 25)
        patch = random.randint(0, 40)
        if major == 1 and minor < 5:
            minor = random.randint(5, 25)
        uri = f"/api/{token}/{secrets.token_hex(5)}"
        cases.append((make_request(uri, f"{major}.{minor}.{patch}"), 0))

    cases.extend([
        (make_request(f"/api/{token}/boundary", "1.5.0"), 0),
        (make_request(f"/api/{token}/multi", "1.10.0"), 0),
        # Traversal text outside the Request-URI must not trigger the URI rule.
        (make_request(f"/api/{token}/safe", "2.0.0", ["X-Decoy: ../%2E%2E%2F"]), 0),
    ])

    for _ in range(10):
        major = random.randint(0, 1)
        if major == 0:
            minor = random.randint(0, 30)
            patch = random.randint(0, 40)
        else:
            minor = random.randint(0, 4)
            patch = random.randint(0, 40)
        cases.append((make_request(f"/api/{token}/{secrets.token_hex(5)}", f"{major}.{minor}.{patch}"), 1))

    cases.extend([
        (make_request(f"/api/{token}/missing"), 1),
        (make_request(f"/api/{token}/../secret", "9.9.9"), 1),
        (make_request(f"/api/{token}/%2e%2e%2fsecret", "9.9.9"), 1),
        (make_request(f"/api/{token}/%2E%2E%2Fsecret", "9.9.9"), 1),
        (make_request(f"/api/{token}/item?next=../secret", "9.9.9"), 1),
    ])
    random.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="waf-generated-") as td:
        for body, expected in cases:
            path = os.path.join(td, secrets.token_hex(12))
            with open(path, "w", newline="") as f:
                f.write(body)
            actual = run_detector(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual, body.splitlines()[0]))

    assert not failures, f"Detector failed generated semantic tests: {failures[:5]}"


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_pids(port):
    inodes = listener_inodes(port)
    pids = set()
    if not inodes:
        return pids
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def proc_info(pid):
    try:
        exe = os.path.realpath(f"/proc/{pid}/exe")
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
        return exe, cmdline
    except (FileNotFoundError, ProcessLookupError):
        return "", ""


def clear_required_ports():
    for _ in range(2):
        pids = set()
        for port in (6379, 8080, 8081, 8082):
            pids.update(listener_pids(port))
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if not pids:
            break
        time.sleep(0.5)


def wait_for_ports(ports, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if all(listener_pids(port) for port in ports):
            return
        time.sleep(0.2)
    missing = [port for port in ports if not listener_pids(port)]
    pytest.fail(f"Services did not listen on required ports: {missing}")


def fetch(url, method="GET", timeout=5):
    req = urllib.request.Request(url, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8")


def assert_port_owner(port, predicate, description):
    infos = [(pid, *proc_info(pid)) for pid in listener_pids(port)]
    assert infos, f"Nothing is listening on port {port}"
    assert any(predicate(exe, cmd) for _, exe, cmd in infos), f"Port {port} is not owned by {description}: {infos}"


def assert_route_depends_on_backend(url, method, backend_port, expected_text):
    pids = listener_pids(backend_port)
    assert pids, f"No backend listener on port {backend_port}"
    for pid in pids:
        os.kill(pid, signal.SIGSTOP)
    try:
        try:
            _, body = fetch(url, method=method, timeout=2)
        except Exception:
            return
        assert expected_text not in body, f"Nginx served {url} without its required backend"
    finally:
        for pid in pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        time.sleep(0.3)


def test_services_integration():
    assert os.path.isfile(START_SCRIPT), f"Missing startup script: {START_SCRIPT}"
    assert os.access(START_SCRIPT, os.X_OK), f"Startup script is not executable: {START_SCRIPT}"

    clear_required_ports()
    subprocess.run([START_SCRIPT], shell=True, check=True, timeout=20)
    wait_for_ports((6379, 8080, 8081, 8082))

    assert_port_owner(6379, lambda exe, cmd: os.path.basename(exe).startswith("redis-server"), "redis-server")
    assert_port_owner(8081, lambda exe, cmd: os.path.basename(exe).startswith("python") and FLASK_APP in cmd, FLASK_APP)
    assert_port_owner(8082, lambda exe, cmd: exe == os.path.realpath(AMD64_PATH), AMD64_PATH)
    assert_port_owner(8080, lambda exe, cmd: os.path.basename(exe).startswith("nginx"), "nginx")

    redis = subprocess.run(["redis-cli", "-p", "6379", "ping"], capture_output=True, text=True, timeout=5)
    assert redis.returncode == 0 and redis.stdout.strip() == "PONG", "Redis did not answer PING"

    status, body = fetch("http://127.0.0.1:8081/api/ping")
    assert status == 200 and "pong" in body, "Flask service is not running on port 8081"
    status, body = fetch("http://127.0.0.1:8082/auth/login", method="POST")
    assert status == 200 and "authenticated" in body, "Compiled Go auth service is not running on port 8082"

    try:
        status, body = fetch("http://127.0.0.1:8080/api/ping")
        assert status == 200 and "pong" in body, "Flask service did not return expected response through Nginx"
    except Exception as e:
        pytest.fail(f"Failed to reach Flask service via Nginx: {e}")

    try:
        status, body = fetch("http://127.0.0.1:8080/auth/login", method="POST")
        assert status == 200 and "authenticated" in body, "Go auth service did not return expected response through Nginx"
    except Exception as e:
        pytest.fail(f"Failed to reach Go auth service via Nginx: {e}")

    assert_route_depends_on_backend("http://127.0.0.1:8080/api/ping", "GET", 8081, "pong")
    assert_route_depends_on_backend("http://127.0.0.1:8080/auth/login", "POST", 8082, "authenticated")

    with open(NGINX_CONF, "r") as f:
        conf_content = f.read()
    assert "proxy_pass" in conf_content, "Nginx config missing proxy_pass directives"
    assert "8081" in conf_content, "Nginx config missing proxy to Flask port 8081"
    assert "8082" in conf_content, "Nginx config missing proxy to Go auth port 8082"

    syntax = subprocess.run(["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True, timeout=10)
    assert syntax.returncode == 0, f"Invalid Nginx configuration: {syntax.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
