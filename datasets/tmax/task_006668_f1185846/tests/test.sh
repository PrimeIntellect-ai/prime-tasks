#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import http.server
import os
import pathlib
import re
import secrets
import signal
import socket
import stat
import subprocess
import threading
import time
import urllib.error
import urllib.request

import pytest

UPSTREAM_BODY = ("SECRET_UPSTREAM_DATA:" + secrets.token_hex(24)).encode()


def tcp_listener_pids(address, port):
    wanted_port = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            if state != "0A" or local.rsplit(":", 1)[1].upper() != wanted_port:
                continue
            inodes.add(inode)

    owners = set()
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(proc.name))
        except OSError:
            pass
    return owners


def unix_socket_pids(path):
    inodes = set()
    try:
        for line in open("/proc/net/unix").read().splitlines()[1:]:
            fields = line.split()
            if len(fields) >= 8 and fields[-1] == path:
                inodes.add(fields[6])
    except OSError:
        pass

    owners = set()
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(proc.name))
        except OSError:
            pass
    return owners


def cmdline(pid):
    try:
        return open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def exe_name(pid):
    try:
        return os.path.basename(os.readlink(f"/proc/{pid}/exe"))
    except OSError:
        return ""


class ChallengeHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(UPSTREAM_BODY)))
        self.end_headers()
        self.wfile.write(UPSTREAM_BODY)

    def log_message(self, *args):
        pass


@pytest.fixture(scope="session", autouse=True)
def controlled_upstream():
    # Replace any setup mock with a verifier-controlled, unpredictable response.
    old_pids = tcp_listener_pids("127.0.0.2", 8080)
    for pid in old_pids:
        with contextlib.suppress(ProcessLookupError):
            os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 2
    while tcp_listener_pids("127.0.0.2", 8080) and time.time() < deadline:
        time.sleep(0.05)
    for pid in tcp_listener_pids("127.0.0.2", 8080):
        with contextlib.suppress(ProcessLookupError):
            os.kill(pid, signal.SIGKILL)

    server = http.server.ThreadingHTTPServer(("127.0.0.2", 8080), ChallengeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def test_ssh_tunnel_active():
    """Test that port 9090 is owned by SSH and forwards fresh upstream data."""
    try:
        response = urllib.request.urlopen("http://127.0.0.1:9090/", timeout=2)
        data = response.read()
        assert b"SECRET_UPSTREAM_DATA" in data, "Port 9090 did not return the expected upstream data."
        assert data == UPSTREAM_BODY, "Port 9090 did not forward the verifier-controlled upstream response."
    except urllib.error.URLError as e:
        pytest.fail(f"Could not connect to tunneled port 9090: {e}")

    owners = tcp_listener_pids("127.0.0.1", 9090)
    assert owners, "No process owns the listening socket on port 9090."
    ssh_owners = [pid for pid in owners if exe_name(pid) == "ssh"]
    assert ssh_owners, "Port 9090 is not being served by an SSH client process."
    assert any("9090:127.0.0.2:8080" in cmdline(pid) for pid in ssh_owners), \
        "The SSH listener was not configured to forward 9090 to 127.0.0.2:8080."


def test_bash_profile_env_var():
    """Test if the environment variable is exported in .bash_profile."""
    bash_profile_path = "/home/user/.bash_profile"
    assert os.path.exists(bash_profile_path), f"File {bash_profile_path} does not exist."
    with open(bash_profile_path, "r") as f:
        content = f.read()
    expected_export = "export TUNNELED_API_URL=http://127.0.0.1:9090"
    assert expected_export in content, f"'{expected_export}' not found in {bash_profile_path}."


def test_backend_script_fixed():
    """Test if the backend script was modified to use the correct socket path."""
    app_path = "/home/user/backend/app.py"
    assert os.path.exists(app_path), f"Backend script missing at {app_path}"
    assert os.path.isfile(app_path), f"Backend script at {app_path} is not a regular file."
    with open(app_path, "r") as f:
        content = f.read()
    assert "/home/user/backend.sock" in content, "Backend script does not contain the new socket path."
    assert "/var/run/backend.sock" not in content, "Backend script still contains the broken socket path."


def request_unix(path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)
    try:
        client.connect(path)
        client.sendall(b"GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")
        response = b""
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            response += chunk
        return response
    finally:
        client.close()


def test_unix_socket_running():
    """Test if app.py is running and serving fresh tunneled data over its Unix socket."""
    sock_path = "/home/user/backend.sock"
    assert os.path.exists(sock_path), f"Unix socket {sock_path} does not exist. Is the backend running?"
    assert stat.S_ISSOCK(os.stat(sock_path).st_mode), f"{sock_path} is not a Unix socket."
    try:
        response = request_unix(sock_path)
        assert b"SECRET_UPSTREAM_DATA" in response, "Unix socket response did not contain the expected upstream data."
        assert response.split(b"\r\n\r\n", 1)[-1] == UPSTREAM_BODY, \
            "The backend did not return the fresh data supplied through the tunnel."
    except Exception as e:
        pytest.fail(f"Failed to communicate with Unix socket: {e}")

    owners = unix_socket_pids(sock_path)
    assert owners, "No running process owns the backend Unix socket."
    assert any(exe_name(pid).startswith("python") and "/home/user/backend/app.py" in cmdline(pid)
               for pid in owners), "The Unix socket is not served by the requested app.py process."


def test_dockerfile_contents():
    """Test if the Dockerfile is created and contains the required directives."""
    dockerfile_path = "/home/user/backend/Dockerfile"
    assert os.path.exists(dockerfile_path), f"Dockerfile missing at {dockerfile_path}"
    with open(dockerfile_path, "r") as f:
        content = f.read()
    assert "FROM python:3.10-slim" in content, "Dockerfile does not use 'python:3.10-slim' as the base image."
    assert "app.py" in content, "Dockerfile does not mention 'app.py'."
    assert "/app" in content, "Dockerfile does not mention the '/app' directory."
    assert "python" in content, "Dockerfile does not set python as part of the command."

    active = [line.strip() for line in content.splitlines()
              if line.strip() and not line.lstrip().startswith("#")]
    assert active and active[0].upper() == "FROM PYTHON:3.10-SLIM", "Dockerfile has an invalid base-image directive."
    assert any(re.match(r"(?i)^COPY\s+app\.py\s+/app(?:/app\.py)?/?$", line) for line in active), \
        "Dockerfile must copy app.py into /app."
    assert any(re.match(r'''(?ix)^CMD\s+(?:\[\s*["']python["']\s*,\s*["']/app/app\.py["']\s*\]|python\s+/app/app\.py)$''', line)
               for line in active), "Dockerfile must set the command to run python /app/app.py."


def test_verification_script_connects_to_unix_socket():
    """Execute verify.py against a controlled Unix server and inspect its request/output."""
    verify_path = "/home/user/verify.py"
    result_path = "/home/user/result.log"
    sock_path = "/home/user/backend.sock"
    saved_path = "/home/user/backend.sock.verifier-saved"
    assert os.path.isfile(verify_path), f"Verification script missing at {verify_path}"

    token = ("VERIFY_SCRIPT_BODY:" + secrets.token_hex(24)).encode()
    received = []
    os.replace(sock_path, saved_path)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        server.bind(sock_path)
        server.listen(1)
        server.settimeout(5)

        def serve_once():
            conn, _ = server.accept()
            with conn:
                conn.settimeout(2)
                data = b""
                while b"\r\n\r\n" not in data:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                received.append(data)
                conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(token)).encode() + b"\r\n\r\n" + token)

        thread = threading.Thread(target=serve_once, daemon=True)
        thread.start()
        with contextlib.suppress(FileNotFoundError):
            os.remove(result_path)
        completed = subprocess.run(["python3", verify_path], timeout=6, capture_output=True, text=True)
        thread.join(timeout=2)
        assert completed.returncode == 0, f"verify.py failed: {completed.stderr}"
        assert received and received[0].startswith(b"GET / "), "verify.py did not make an HTTP GET request to /."
        assert os.path.isfile(result_path), "verify.py did not create /home/user/result.log."
        assert open(result_path, "rb").read() == token, "verify.py did not write the raw controlled response body."
    finally:
        server.close()
        with contextlib.suppress(FileNotFoundError):
            os.remove(sock_path)
        os.replace(saved_path, sock_path)

    # Generate the final requested log using the real running backend.
    completed = subprocess.run(["python3", verify_path], timeout=6, capture_output=True, text=True)
    assert completed.returncode == 0, f"verify.py failed against the backend: {completed.stderr}"


def test_result_log():
    """Test if the verification script successfully wrote the result to result.log."""
    log_path = "/home/user/result.log"
    assert os.path.exists(log_path), f"Log file missing at {log_path}"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "SECRET_UPSTREAM_DATA" in content, f"Log file {log_path} does not contain the expected data."
    assert content == UPSTREAM_BODY.decode(), "result.log was not generated from the fresh backend response."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
