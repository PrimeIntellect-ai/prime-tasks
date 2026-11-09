#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import signal
import string
import subprocess
import sys
import tempfile
import time
import urllib.request


def slugify(value):
    result = []
    for char in value:
        if char.isalnum():
            result.append(char.lower() if char.isascii() else char)
        elif char.isspace() or char == "-":
            if result and result[-1] != "-":
                result.append("-")
    return "".join(result).rstrip("-")


def post(url, body):
    request = urllib.request.Request(url, data=body.encode(), method="POST")
    with urllib.request.urlopen(request, timeout=3) as response:
        return response.status, response.read().decode(), response.headers


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def wait_for_port_state(port, listening, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        present = bool(listener_pids(port))
        if present == listening:
            return
        time.sleep(0.05)
    raise AssertionError(f"port {port} did not reach listening={listening}")


def test_backend_artifact_and_cli_fuzz():
    agent_path = "/home/user/backend-bin"
    assert os.path.isfile(agent_path), f"Agent binary {agent_path} not found"
    assert os.access(agent_path, os.X_OK), f"Agent binary {agent_path} not executable"
    with open(agent_path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "backend-bin is not a compiled executable"

    random.seed(42)
    printable = string.printable
    for _ in range(100):
        length = random.randint(5, 50)
        input_str = "".join(random.choice(printable) for _ in range(length))
        result = subprocess.run([agent_path, input_str], capture_output=True, text=True, timeout=3)
        assert result.returncode == 0, f"Agent failed on input {input_str!r}"
        expected = slugify(input_str)
        assert result.stdout == expected, (
            f"Output mismatch on input {input_str!r}: expected {expected!r}, got {result.stdout!r}"
        )


def test_live_backend_and_nginx_stack():
    backend_path = os.path.realpath("/home/user/backend-bin")
    backend_pids = listener_pids(8080)
    assert backend_pids, "nothing is listening on backend port 8080"
    assert any(
        os.path.realpath(f"/proc/{pid}/exe") == backend_path
        for pid in backend_pids
        if os.path.exists(f"/proc/{pid}/exe")
    ), "port 8080 is not served by /home/user/backend-bin"

    assert os.path.isfile("/tmp/nginx.pid"), "unprivileged Nginx is not running"
    with open("/tmp/nginx.pid") as handle:
        nginx_pid = int(handle.read().strip())
    assert os.path.exists(f"/proc/{nginx_pid}"), "Nginx master PID is not running"
    with open(f"/proc/{nginx_pid}/status") as handle:
        status = handle.read()
    uid_line = next(line for line in status.splitlines() if line.startswith("Uid:"))
    assert int(uid_line.split()[1]) != 0, "Nginx master is running as root"
    assert os.path.basename(os.readlink(f"/proc/{nginx_pid}/exe")) == "nginx"

    samples = [
        "Hello World 123",
        "health check 1",
        "Rust--Slugger 2026",
        "  Mixed punctuation! 42? test  ",
    ]
    random.seed(731)
    alphabet = string.ascii_letters + string.digits + " -_!?.,"
    samples.extend("".join(random.choice(alphabet) for _ in range(30)) for _ in range(20))

    for value in samples:
        expected = slugify(value)
        direct_status, direct_body, _ = post("http://127.0.0.1:8080/process", value)
        assert direct_status == 200
        assert direct_body == expected

        proxy_status, proxy_body, headers = post("http://127.0.0.1:9090/process", value)
        assert proxy_status == 200
        assert proxy_body == expected
        assert "nginx" in headers.get("Server", "").lower(), "port 9090 is not served by Nginx"


def test_health_script():
    health_script = "/home/user/health.sh"
    assert os.path.isfile(health_script), f"{health_script} does not exist"
    assert os.access(health_script, os.X_OK), f"{health_script} is not executable"

    result = subprocess.run([health_script], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, (
        f"{health_script} failed with exit code {result.returncode}, stderr: {result.stderr}"
    )

    with open("/tmp/nginx.pid") as handle:
        nginx_pid = int(handle.read().strip())

    fake_server = r'''
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

capture_path = sys.argv[1]
class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode()
        with open(capture_path, "w") as handle:
            json.dump({"method": "POST", "path": self.path, "body": body}, handle)
        payload = b"definitely-wrong"
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, *args):
        pass

server = ReusableHTTPServer(("127.0.0.1", 9090), Handler)
server.timeout = 8
server.handle_request()
'''

    capture = tempfile.NamedTemporaryFile(delete=False)
    capture.close()
    os.unlink(capture.name)
    fake = None
    try:
        os.kill(nginx_pid, signal.SIGTERM)
        wait_for_port_state(9090, False)
        fake = subprocess.Popen([sys.executable, "-c", fake_server, capture.name])
        time.sleep(0.2)

        bad_result = subprocess.run([health_script], capture_output=True, text=True, timeout=5)
        assert bad_result.returncode == 1, (
            "health.sh must exit 1 when the endpoint response is not exactly health-check-1"
        )
        fake.wait(timeout=5)
        assert os.path.isfile(capture.name), "health.sh did not send a request to port 9090"
        with open(capture.name) as handle:
            request = json.load(handle)
        assert request == {"method": "POST", "path": "/process", "body": "health check 1"}
    finally:
        if fake is not None and fake.poll() is None:
            fake.terminate()
            fake.wait(timeout=3)
        try:
            os.unlink(capture.name)
        except FileNotFoundError:
            pass
        subprocess.run(
            ["runuser", "-u", "user", "--", "nginx", "-c", "/home/user/nginx.conf"],
            check=True,
            capture_output=True,
            text=True,
        )
        wait_for_port_state(9090, True)

    status, body, _ = post("http://127.0.0.1:9090/process", "health check 1")
    assert status == 200 and body == "health-check-1"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
