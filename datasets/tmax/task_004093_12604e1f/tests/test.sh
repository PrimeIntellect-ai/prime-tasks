#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import signal
import socket
import stat
import subprocess
import time
import urllib.error
import urllib.request

import pytest

CONF = "/home/user/nginx/nginx.conf"
EXPECT_SCRIPT = "/home/user/start_backend.exp"
DEPLOY_SCRIPT = "/home/user/deploy.py"
SERVER_SCRIPT = "/home/user/app/server.py"
SOCKET_PATH = "/home/user/app/backend.sock"
STATUS_LOG = "/home/user/deploy_status.log"
TOKEN = secrets.token_hex(16)


def listening_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            pass
    return pids


def process_cmdlines():
    result = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
            result[int(entry)] = raw.replace(b"\0", b" ").decode(errors="replace")
        except OSError:
            pass
    return result


def cleanup_services():
    victims = set(listening_pids(8080))
    for pid, cmd in process_cmdlines().items():
        if pid == os.getpid():
            continue
        if ("nginx" in cmd or SERVER_SCRIPT in cmd or EXPECT_SCRIPT in cmd or DEPLOY_SCRIPT in cmd):
            victims.add(pid)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)
    for path in (SOCKET_PATH, "/home/user/nginx/nginx.pid"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def unix_health():
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(2)
    try:
        sock.connect(SOCKET_PATH)
        sock.sendall(b"GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n")
        data = b""
        while True:
            part = sock.recv(4096)
            if not part:
                break
            data += part
    finally:
        sock.close()
    head, body = data.split(b"\r\n\r\n", 1)
    assert b" 200 " in head.splitlines()[0]
    assert body.strip() == b"OK"
    assert (b"X-Backend-Challenge: " + TOKEN.encode()).lower() in head.lower()


def run_as_user(args, timeout):
    return subprocess.run(
        ["runuser", "-u", "user", "--"] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )


@pytest.fixture(scope="session", autouse=True)
def controlled_backend():
    original = open(SERVER_SCRIPT, "rb").read()
    original_mode = stat.S_IMODE(os.stat(SERVER_SCRIPT).st_mode)
    challenge = f'''#!/usr/bin/env python3
import http.server
import os
import socketserver
import sys

socket_path = {SOCKET_PATH!r}
sys.stdout.write("Enter startup key: ")
sys.stdout.flush()
key = sys.stdin.readline().strip()
if key != "DeployKey2023!":
    print("Invalid key. Exiting.")
    sys.exit(23)
print("Key accepted. Starting server...")
sys.stdout.flush()
if os.path.exists(socket_path):
    os.remove(socket_path)

class Server(socketserver.UnixStreamServer):
    def get_request(self):
        request, address = self.socket.accept()
        return request, ["local"]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("X-Backend-Challenge", {TOKEN!r})
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *args):
        pass

with Server(socket_path, Handler) as server:
    os.chmod(socket_path, 0o777)
    server.serve_forever()
'''
    cleanup_services()
    with open(SERVER_SCRIPT, "w") as f:
        f.write(challenge)
    os.chmod(SERVER_SCRIPT, 0o755)
    try:
        yield
    finally:
        with open(SERVER_SCRIPT, "wb") as f:
            f.write(original)
        os.chmod(SERVER_SCRIPT, original_mode)


def test_required_automation_artifacts():
    assert os.path.isfile(EXPECT_SCRIPT), f"Expect startup script missing at {EXPECT_SCRIPT}"
    assert os.path.isfile(DEPLOY_SCRIPT), f"Deployment script missing at {DEPLOY_SCRIPT}"

    expect_source = open(EXPECT_SCRIPT).read()
    assert "/home/user/app/server.py" in expect_source, "Expect script does not target server.py"
    assert "Enter startup key:" in expect_source, "Expect script does not wait for the startup prompt"
    assert "DeployKey2023!" in expect_source, "Expect script does not send the required startup key"
    assert "spawn" in expect_source and "expect" in expect_source and "send" in expect_source, \
        "Expect script is missing required expect automation commands"

    deploy_source = open(DEPLOY_SCRIPT).read()
    try:
        tree = ast.parse(deploy_source)
    except SyntaxError as exc:
        pytest.fail(f"deploy.py is not valid Python: {exc}")

    strings = "\n".join(
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    )
    assert "/home/user/start_backend.exp" in strings, "deploy.py does not execute start_backend.exp"
    assert "nginx" in strings and "-c" in strings and "/home/user/nginx/nginx.conf" in strings \
        and "-p" in strings and "/home/user/nginx" in strings, \
        "deploy.py does not contain the required Nginx command and arguments"
    assert "http://127.0.0.1:8080/health" in strings, "deploy.py does not poll the required health URL"
    assert "DEPLOYMENT_SUCCESS: 200 OK" in strings, "deploy.py does not write the required success value"
    assert any(isinstance(node, (ast.For, ast.While)) for node in ast.walk(tree)), \
        "deploy.py has no retry loop"
    assert any(
        isinstance(node, ast.Call)
        and ((isinstance(node.func, ast.Attribute) and node.func.attr == "sleep")
             or (isinstance(node.func, ast.Name) and node.func.id == "sleep"))
        for node in ast.walk(tree)
    ), "deploy.py has no retry backoff delay"


def test_start_backend_expect_script_really_answers_prompt():
    cleanup_services()
    proc = subprocess.Popen(
        ["runuser", "-u", "user", "--", "expect", EXPECT_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    deadline = time.time() + 12
    while time.time() < deadline and not os.path.exists(SOCKET_PATH):
        if proc.poll() is not None:
            output = proc.stdout.read() if proc.stdout else ""
            pytest.fail(f"start_backend.exp exited before starting the backend: {output}")
        time.sleep(0.1)
    assert os.path.exists(SOCKET_PATH), "start_backend.exp did not create the backend Unix socket"
    unix_health()
    assert any(SERVER_SCRIPT in cmd for cmd in process_cmdlines().values()), \
        "start_backend.exp did not spawn /home/user/app/server.py"


def test_deploy_handles_backend_start_failure():
    cleanup_services()
    try:
        os.unlink(STATUS_LOG)
    except FileNotFoundError:
        pass

    original = open(EXPECT_SCRIPT, "rb").read()
    mode = stat.S_IMODE(os.stat(EXPECT_SCRIPT).st_mode)
    try:
        with open(EXPECT_SCRIPT, "w") as f:
            f.write("#!/usr/bin/expect -f\nexit 7\n")
        os.chmod(EXPECT_SCRIPT, 0o755)
        try:
            result = run_as_user(["python3", DEPLOY_SCRIPT], timeout=50)
        except subprocess.TimeoutExpired:
            pytest.fail("deploy.py did not gracefully exit when backend startup failed")
        assert result.returncode != 0, \
            f"deploy.py reported success despite backend startup failure. Output: {result.stdout}"
        assert not os.path.exists(STATUS_LOG) or open(STATUS_LOG).read().strip() != "DEPLOYMENT_SUCCESS: 200 OK", \
            "deploy.py wrote a success log despite backend startup failure"
    finally:
        with open(EXPECT_SCRIPT, "wb") as f:
            f.write(original)
        os.chmod(EXPECT_SCRIPT, mode)


def test_running_deploy_script_creates_real_deployment():
    cleanup_services()
    try:
        os.unlink(STATUS_LOG)
    except FileNotFoundError:
        pass

    result = run_as_user(["python3", DEPLOY_SCRIPT], timeout=50)
    assert result.returncode == 0, f"deploy.py failed. Output: {result.stdout}"
    assert os.path.exists(SOCKET_PATH), "Backend Unix socket was not created by deploy.py"
    assert any(SERVER_SCRIPT in cmd for cmd in process_cmdlines().values()), \
        "The required backend server is not running"
    assert any("nginx" in cmd and "-c /home/user/nginx/nginx.conf" in cmd \
               and "-p /home/user/nginx" in cmd for cmd in process_cmdlines().values()), \
        "Nginx was not started with the required configuration and prefix"

    with urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=5) as response:
        assert response.getcode() == 200
        assert response.read().decode().strip() == "OK"
        assert response.headers.get("X-Backend-Challenge") == TOKEN, \
            "Port 8080 is not proxying to the backend launched through start_backend.exp"


def test_nginx_config_fixed():
    """Verify that the Nginx configuration points to the correct socket."""
    conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx configuration missing at {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    assert "server unix:/home/user/app/backend.sock;" in content, \
        "Nginx configuration does not have the correct upstream socket path (/home/user/app/backend.sock)."


def test_deploy_status_log():
    """Verify the deployment script created the correct log file with the expected contents."""
    log_path = "/home/user/deploy_status.log"
    assert os.path.isfile(log_path), f"Deployment log missing at {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "DEPLOYMENT_SUCCESS: 200 OK", \
        f"Deployment log content is incorrect. Expected 'DEPLOYMENT_SUCCESS: 200 OK', got '{content}'."


def test_health_endpoint():
    """Verify that the Nginx server and backend are running and responding correctly."""
    url = "http://127.0.0.1:8080/health"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.getcode()
            body = response.read().decode('utf-8').strip()

            assert status == 200, f"Expected HTTP 200 OK, got {status}."
            assert body == "OK", f"Expected body 'OK', got '{body}'."
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to Nginx at {url}: {e}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
