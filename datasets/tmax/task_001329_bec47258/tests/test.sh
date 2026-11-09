#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import cv2
import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
import pytest

VIDEO = "/app/secret_architecture.mp4"
PROJECT = "/home/user/clean_project"
VENV_PYTHON = "/home/user/venv/bin/python"
PROXY = os.path.join(PROJECT, "proxy.py")
USER_TESTS = os.path.join(PROJECT, "tests/test_proxy.py")


def decode_config():
    cap = cv2.VideoCapture(VIDEO)
    chars = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        value = int(frame[0, 0, 2])
        if value == 0:
            break
        chars.append(chr(value))
    cap.release()
    return json.loads("".join(chars))


CONFIG = decode_config()
ROUTES = CONFIG["routes"]
MAPPING = CONFIG["file_mapping"]


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[-1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass
    pids = set()
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
        except OSError:
            pass
    return pids


def kill_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def stop_process(proc):
    if proc and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def request_json(path, method="GET", body=None, headers=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:8000" + path,
        data=data,
        method=method,
        headers=headers or {},
    )
    with urllib.request.urlopen(req, timeout=3) as response:
        return response.status, json.loads(response.read().decode())


def backend_for_route(prefix):
    key = prefix.strip("/").rstrip("s").lower()
    matches = [target for target in MAPPING.values() if key in os.path.basename(target).lower()]
    assert len(matches) == 1, f"Cannot associate {prefix} with one decoded backend"
    return os.path.join(PROJECT, matches[0])


def launch_proxy():
    commands = [
        [VENV_PYTHON, PROXY],
        [VENV_PYTHON, "-m", "uvicorn", "proxy:app", "--host", "127.0.0.1", "--port", "8000"],
        [VENV_PYTHON, "-m", "flask", "--app", "proxy:app", "run", "--host", "127.0.0.1", "--port", "8000"],
    ]
    for command in commands:
        kill_port(8000)
        proc = subprocess.Popen(command, cwd=PROJECT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if wait_port(8000, timeout=5):
            return proc
        stop_process(proc)
    pytest.fail("proxy.py could not be executed as the server on port 8000")


@pytest.fixture(scope="session")
def running_system():
    ports = {int(port) for port in ROUTES.values()}
    for port in ports | {8000}:
        kill_port(port)

    backends = []
    proxy = None
    try:
        for prefix, port_value in ROUTES.items():
            port = int(port_value)
            script = backend_for_route(prefix)
            proc = subprocess.Popen(
                [VENV_PYTHON, script, "--port", str(port)],
                cwd=PROJECT,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            backends.append(proc)
            assert wait_port(port), f"backend {script} did not start on decoded port {port}"
        proxy = launch_proxy()
        yield {"backends": backends, "proxy": proxy}
    finally:
        stop_process(proxy)
        for proc in backends:
            stop_process(proc)
        for port in ports | {8000}:
            kill_port(port)


def test_files_moved_to_clean_project():
    auth_path = "/home/user/clean_project/backends/auth_service.py"
    user_path = "/home/user/clean_project/backends/user_service.py"

    assert os.path.isfile(auth_path), f"Expected file not found: {auth_path}"
    assert os.path.isfile(user_path), f"Expected file not found: {user_path}"

    assert not os.path.exists("/home/user/messy_files/auth_service.py"), "auth_service.py should be moved, not copied."
    assert not os.path.exists("/home/user/messy_files/user_service.py"), "user_service.py should be moved, not copied."

    for source, target in MAPPING.items():
        assert os.path.isfile(os.path.join(PROJECT, target))
        assert not os.path.exists(os.path.join("/home/user/messy_files", source))


def test_required_project_artifacts():
    assert os.path.isfile(PROXY), "proxy.py was not created"
    assert os.path.isfile("/home/user/venv/pyvenv.cfg"), "virtual environment was not created"
    assert os.path.isfile(VENV_PYTHON) and os.access(VENV_PYTHON, os.X_OK)
    assert os.path.isfile(USER_TESTS), "tests/test_proxy.py was not created"

    source = open(USER_TESTS, encoding="utf-8").read()
    tree = ast.parse(source)
    tests = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith("test_")]
    assert tests, "tests/test_proxy.py contains no test functions"
    assert "8000" in source
    for prefix in ROUTES:
        assert prefix in source, f"submitted tests do not exercise decoded route {prefix}"


def test_reverse_proxy_accuracy(running_system):
    correct = 0
    total = 2
    try:
        _, data = request_json("/auth")
        if data.get("service") == "auth":
            correct += 1
    except Exception:
        pass
    try:
        _, data = request_json("/users")
        if data.get("service") == "user":
            correct += 1
    except Exception:
        pass
    accuracy = correct / total
    assert accuracy >= 1.0, f"Reverse proxy routing accuracy is {accuracy}, expected >= 1.0. Correctly routed {correct} out of {total} endpoints."


def test_submitted_test_suite_passes(running_system):
    result = subprocess.run(
        [sys.executable, "-m", "pytest", USER_TESTS, "-q"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, "submitted proxy tests failed:\n" + result.stdout


def test_dynamic_transparent_forwarding(running_system, tmp_path):
    for proc in running_system["backends"]:
        stop_process(proc)
    for port in {int(p) for p in ROUTES.values()}:
        kill_port(port)

    helper = tmp_path / "echo_backend.py"
    helper.write_text(r'''import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
port, token = int(sys.argv[1]), sys.argv[2]
class H(BaseHTTPRequestHandler):
    def reply(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode() if length else ""
        data = {"backend_token": token, "method": self.command, "path": self.path,
                "test_header": self.headers.get("X-Proxy-Verification"), "body": body}
        raw = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
    do_GET = reply
    do_POST = reply
    def log_message(self, *args): pass
HTTPServer(("127.0.0.1", port), H).serve_forever()
''', encoding="utf-8")

    echoes = []
    tokens = {}
    try:
        for prefix, port_value in ROUTES.items():
            port = int(port_value)
            token = uuid.uuid4().hex
            tokens[prefix] = token
            proc = subprocess.Popen([sys.executable, str(helper), str(port), token], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            echoes.append(proc)
            assert wait_port(port), f"test backend failed to start on {port}"

        for prefix in ROUTES:
            suffix = "/probe-" + uuid.uuid4().hex
            query = "?q=" + uuid.uuid4().hex
            header_value = uuid.uuid4().hex
            payload = {"nonce": uuid.uuid4().hex, "route": prefix}
            status, data = request_json(
                prefix + suffix + query,
                method="POST",
                body=payload,
                headers={"Content-Type": "application/json", "X-Proxy-Verification": header_value},
            )
            assert status == 200
            assert data["backend_token"] == tokens[prefix], "request reached the wrong backend"
            assert data["method"] == "POST"
            assert data["test_header"] == header_value, "custom header was not forwarded"
            assert json.loads(data["body"]) == payload, "JSON body was not forwarded"
            assert data["path"] == suffix.join([prefix, ""]) + query

            _, get_data = request_json(prefix + suffix, headers={"X-Proxy-Verification": header_value})
            assert get_data["backend_token"] == tokens[prefix]
            assert get_data["method"] == "GET"
    finally:
        for proc in echoes:
            stop_process(proc)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
