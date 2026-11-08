#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import signal
import socket
import stat
import subprocess
import time
import urllib.error
import urllib.request
import uuid

import pytest

APP_DIR = "/home/user/app"
START_SCRIPT = APP_DIR + "/start_app.sh"
SOCKET_PATH = APP_DIR + "/app.sock"
NGINX_CONF = "/home/user/nginx/nginx.conf"
USER = pwd.getpwnam("user")


def run_as_user(path, cwd, timeout=10):
    def demote():
        os.setsid()
        os.setgid(USER.pw_gid)
        os.setuid(USER.pw_uid)

    return subprocess.run(
        path,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        preexec_fn=demote,
    )


def matching_processes(predicate):
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            with open(f"/proc/{entry}/comm", "r") as f:
                comm = f.read().strip()
            st = os.stat(f"/proc/{entry}")
            if predicate(int(entry), st.st_uid, comm, cmdline):
                found.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found


def terminate_processes(pids):
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    remaining = set(pids)
    while remaining and time.time() < deadline:
        remaining = {pid for pid in remaining if os.path.exists(f"/proc/{pid}")}
        time.sleep(0.05)
    for pid in remaining:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def kill_existing_app_servers():
    pids = matching_processes(
        lambda pid, uid, comm, cmd: uid == USER.pw_uid and "server.py" in cmd
    )
    terminate_processes(pids)


def kill_existing_nginx():
    pids = matching_processes(lambda pid, uid, comm, cmd: comm == "nginx")
    terminate_processes(pids)
    try:
        os.unlink("/home/user/nginx/nginx.pid")
    except FileNotFoundError:
        pass


def wait_for_socket(path, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if stat.S_ISSOCK(os.stat(path).st_mode):
                return
        except FileNotFoundError:
            pass
        time.sleep(0.1)
    pytest.fail(f"Timed out waiting for Unix socket {path}")


def unix_http_request(path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(5)
    try:
        client.connect(path)
        client.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        chunks = []
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks)
    finally:
        client.close()


def wait_for_http(url, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                return response.getcode(), response.read().decode("utf-8")
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"Timed out waiting for {url}: {last_error}")


def test_start_app_sh_fixed():
    path = START_SCRIPT
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "/home/user/app" in content, "start_app.sh does not seem to change to or reference the correct directory."

    kill_existing_app_servers()
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass

    arbitrary_cwd = "/tmp/start-app-verifier"
    os.makedirs(arbitrary_cwd, exist_ok=True)
    os.chmod(arbitrary_cwd, 0o777)
    result = run_as_user(["/bin/bash", path], arbitrary_cwd)
    assert result.returncode == 0, f"start_app.sh failed: {result.stderr}"
    wait_for_socket(SOCKET_PATH)

    response = unix_http_request(SOCKET_PATH)
    assert b"HTTP/1.1 200" in response
    assert b"Hello from Python app!" in response

    app_processes = matching_processes(
        lambda pid, uid, comm, cmd: uid == USER.pw_uid and "server.py" in cmd
    )
    assert app_processes, "Executing start_app.sh did not start server.py"
    assert any(
        os.path.realpath(f"/proc/{pid}/cwd") == APP_DIR
        for pid in app_processes
        if os.path.exists(f"/proc/{pid}/cwd")
    ), "server.py was not started with /home/user/app as its working directory"


def test_nginx_conf_fixed():
    path = NGINX_CONF
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "proxy_pass http://unix:/home/user/app/app.sock;" in content, "Nginx config proxy_pass is not pointing to the correct socket."
    assert "403" in content, "Nginx config does not seem to contain a 403 rule for /admin."

    kill_existing_nginx()
    result = run_as_user(["nginx", "-c", path], "/home/user")
    assert result.returncode == 0, f"Nginx failed to start with the submitted configuration: {result.stderr}"
    status, body = wait_for_http("http://127.0.0.1:8080/")
    assert status == 200
    assert "Hello from Python app!" in body


def test_rotate_logs_script_exists():
    path = "/home/user/app/rotate_logs.py"
    assert os.path.isfile(path), f"Log rotation script missing: {path}"


def test_rotate_logs_script_behavior():
    script = "/home/user/app/rotate_logs.py"
    log_path = "/home/user/app/app.log"
    archive_path = "/home/user/app/app.log.archive"
    marker = ("rotation-marker-" + uuid.uuid4().hex + "\n").encode()

    with open(archive_path, "wb") as f:
        f.write(b"old archive must be overwritten\n")
    with open(log_path, "wb") as f:
        f.write(marker)
    os.chown(log_path, USER.pw_uid, USER.pw_gid)
    os.chown(archive_path, USER.pw_uid, USER.pw_gid)
    original_inode = os.stat(log_path).st_ino

    result = run_as_user(["python3", script], APP_DIR)
    assert result.returncode == 0, f"rotate_logs.py failed: {result.stderr}"
    assert os.path.isfile(archive_path), f"Archive log missing: {archive_path}"
    assert os.stat(archive_path).st_ino == original_inode, "app.log was not renamed to app.log.archive"
    with open(archive_path, "rb") as f:
        assert f.read() == marker, "The archive does not contain the pre-rotation log data"
    assert os.path.isfile(log_path), f"New log file missing: {log_path}"
    with open(log_path, "rb") as f:
        assert f.read() == b"", "The newly created app.log is not empty"
    assert stat.S_IMODE(os.stat(log_path).st_mode) == 0o644


def test_log_files_exist_and_permissions():
    log_path = "/home/user/app/app.log"
    archive_path = "/home/user/app/app.log.archive"

    assert os.path.isfile(archive_path), f"Archive log missing: {archive_path}"
    assert os.path.isfile(log_path), f"New log file missing: {log_path}"

    st = os.stat(log_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o644, f"Permissions for {log_path} are {oct(perms)}, expected 0o644"


def test_socket_exists():
    sock_path = "/home/user/app/app.sock"
    assert os.path.exists(sock_path), f"Socket missing: {sock_path}"
    assert stat.S_ISSOCK(os.stat(sock_path).st_mode), f"Path {sock_path} is not a socket"


def test_http_root_returns_success():
    url = "http://127.0.0.1:8080/"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.getcode()
            body = response.read().decode('utf-8')
    except Exception as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert status == 200, f"Expected status 200, got {status}"
    assert "Hello from Python app!" in body, "Response body does not contain the expected text."


def test_http_admin_returns_403():
    url = "http://127.0.0.1:8080/admin"
    try:
        req = urllib.request.Request(url)
        urllib.request.urlopen(req, timeout=5)
        pytest.fail("Expected a 403 Forbidden error, but request succeeded.")
    except urllib.error.HTTPError as e:
        assert e.code == 403, f"Expected status 403, got {e.code}"
    except Exception as e:
        pytest.fail(f"Unexpected error when connecting to {url}: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
