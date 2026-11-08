#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import socket
import subprocess
import time
import urllib.error
import urllib.request
import uuid

import pytest

DATA_DIR = "/home/user/data"
SOCKET_PATH = "/home/user/run/app.sock"


def get_expected_size():
    total_size = 0
    if os.path.isdir(DATA_DIR):
        for entry in os.listdir(DATA_DIR):
            path = os.path.join(DATA_DIR, entry)
            if os.path.isfile(path) and not os.path.islink(path):
                total_size += os.path.getsize(path)
    return total_size


@pytest.fixture(scope="session", autouse=True)
def deploy_from_script():
    deploy = "/home/user/deploy.sh"
    assert os.path.isfile(deploy), f"Deployment script {deploy} does not exist"
    subprocess.run(["bash", "-n", deploy], check=True)

    # Ensure the submitted script really recreates and starts the stack as the
    # unprivileged user, rather than relying on artifacts left from before.
    subprocess.run(["pkill", "-TERM", "-x", "monitor"], check=False)
    subprocess.run(["pkill", "-TERM", "-x", "nginx"], check=False)
    time.sleep(1)
    subprocess.run(["pkill", "-KILL", "-x", "monitor"], check=False)
    subprocess.run(["pkill", "-KILL", "-x", "nginx"], check=False)

    for path in (SOCKET_PATH, "/home/user/run/nginx.pid", "/home/user/bin/monitor"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", deploy],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
    )
    assert completed.returncode == 0, "deploy.sh failed when executed as user"
    time.sleep(2)


def _without_comments(text):
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


def _directive_value(config, name):
    match = re.search(r"(?m)^\s*" + re.escape(name) + r"\s+([^;\s]+)", config)
    assert match, f"Missing required Nginx directive: {name}"
    return match.group(1)


def test_required_source_script_and_nginx_configuration():
    source_path = "/home/user/src/monitor.c"
    deploy_path = "/home/user/deploy.sh"
    config_path = "/home/user/nginx/nginx.conf"

    assert os.path.isfile(source_path), f"C source {source_path} does not exist"
    assert os.path.getsize(source_path) > 0, f"C source {source_path} is empty"
    assert os.path.isfile(deploy_path), f"Deployment script {deploy_path} does not exist"
    assert os.path.getsize(deploy_path) > 0, f"Deployment script {deploy_path} is empty"
    assert os.path.isfile(config_path), f"Nginx configuration {config_path} does not exist"

    with open(deploy_path, "r", encoding="utf-8") as f:
        deploy_text = _without_comments(f.read())
    assert re.search(r"\b(?:gcc|cc)\b", deploy_text), "deploy.sh does not invoke a C compiler"
    assert "monitor.c" in deploy_text, "deploy.sh does not compile monitor.c"
    assert re.search(r"\bnginx\b", deploy_text), "deploy.sh does not start Nginx"
    assert "nginx.conf" in deploy_text, "deploy.sh does not use the custom nginx.conf"

    with open(config_path, "r", encoding="utf-8") as f:
        config = _without_comments(f.read())

    assert not re.search(r"(?m)^\s*user\s+", config), "The Nginx user directive must not be used"
    assert _directive_value(config, "pid") == "/home/user/run/nginx.pid"
    assert _directive_value(config, "error_log") == "/home/user/nginx/error.log"
    assert _directive_value(config, "access_log") == "/home/user/nginx/access.log"
    assert re.search(r"(?m)^\s*listen\s+127\.0\.0\.1:8080(?:\s|;)", config), \
        "Nginx must listen on 127.0.0.1:8080"
    assert re.search(r"\blocation\s+(?:(?:=|\^~)\s+)?/status(?:\s|\{)", config), \
        "Nginx must define a location for /status"
    assert re.search(r"(?m)^\s*proxy_pass\s+[^;]*unix:/home/user/run/app\.sock", config), \
        "The /status proxy must use /home/user/run/app.sock"

    for directive in (
        "client_body_temp_path",
        "proxy_temp_path",
        "fastcgi_temp_path",
        "uwsgi_temp_path",
        "scgi_temp_path",
    ):
        value = _directive_value(config, directive)
        assert value.startswith("/home/user/nginx/tmp/"), \
            f"{directive} must point inside /home/user/nginx/tmp/"


def test_monitor_executable_exists():
    exe_path = "/home/user/bin/monitor"
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "monitor is not a compiled native executable"


def test_socket_exists_and_is_socket():
    assert os.path.exists(SOCKET_PATH), f"Socket {SOCKET_PATH} does not exist"
    mode = os.stat(SOCKET_PATH).st_mode
    assert stat.S_ISSOCK(mode), f"Path {SOCKET_PATH} exists but is not a UNIX domain socket"


def test_result_log_content():
    log_path = "/home/user/result.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist"
    with open(log_path, "r") as f:
        content = f.read().strip()
    expected_size = get_expected_size()
    expected_str = f"USAGE: {expected_size}"
    assert content == expected_str, f"result.log content is incorrect. Expected '{expected_str}', got '{content}'"


def _direct_backend_response():
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)
    try:
        client.connect(SOCKET_PATH)
        client.sendall(b"GET /status HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        chunks = []
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        client.close()

    raw = b"".join(chunks)
    assert b"\r\n\r\n" in raw, "Backend did not return a valid HTTP header/body separator"
    headers, body = raw.split(b"\r\n\r\n", 1)
    lines = headers.split(b"\r\n")
    assert lines[0] == b"HTTP/1.1 200 OK", f"Incorrect backend status line: {lines[0]!r}"
    assert any(line.lower().startswith(b"content-type:") and b"text/plain" in line.lower()
               for line in lines[1:]), "Backend response lacks Content-Type: text/plain"
    return body


def _nginx_response():
    try:
        req = urllib.request.Request("http://127.0.0.1:8080/status")
        with urllib.request.urlopen(req, timeout=3) as response:
            assert response.status == 200
            return response.read()
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx on 127.0.0.1:8080: {e}")


def test_nginx_proxy_dynamic_response():
    expected_size = get_expected_size()
    expected_str = f"USAGE: {expected_size}"
    content = _nginx_response().decode("utf-8").strip()
    assert content == expected_str, f"HTTP response is incorrect. Expected '{expected_str}', got '{content}'"


def test_backend_recomputes_immediate_file_usage_after_changes():
    token = uuid.uuid4().hex
    added_file = os.path.join(DATA_DIR, f"verifier_{token}.bin")
    subdir = os.path.join(DATA_DIR, f"verifier_dir_{token}")
    nested_file = os.path.join(subdir, "must_not_be_counted.bin")
    first_size = 2048 + int(token[:4], 16) % 4096
    extra_size = 257 + int(token[4:8], 16) % 1024

    try:
        os.mkdir(subdir)
        with open(nested_file, "wb") as f:
            f.write(os.urandom(3333))
        with open(added_file, "wb") as f:
            f.write(os.urandom(first_size))

        expected = get_expected_size()
        expected_body = f"USAGE: {expected}\n".encode()
        assert _direct_backend_response() == expected_body
        assert _nginx_response() == expected_body

        with open(added_file, "ab") as f:
            f.write(os.urandom(extra_size))
        expected = get_expected_size()
        expected_body = f"USAGE: {expected}\n".encode()
        assert _direct_backend_response() == expected_body
        assert _nginx_response() == expected_body
    finally:
        try:
            os.unlink(added_file)
        except FileNotFoundError:
            pass
        try:
            os.unlink(nested_file)
        except FileNotFoundError:
            pass
        try:
            os.rmdir(subdir)
        except FileNotFoundError:
            pass


def test_processes_running():
    try:
        subprocess.check_output(["pgrep", "-f", "monitor"])
    except subprocess.CalledProcessError:
        pytest.fail("The 'monitor' process is not running")

    try:
        subprocess.check_output(["pgrep", "-f", "nginx"])
    except subprocess.CalledProcessError:
        pytest.fail("The 'nginx' process is not running")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
