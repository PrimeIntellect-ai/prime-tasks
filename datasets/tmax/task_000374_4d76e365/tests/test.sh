#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import signal
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
import requests

SERVICES = ["kv_store.py", "backend.py", "frontend.py"]
SERVICE_PATHS = [f"/app/{name}" for name in SERVICES]

EXPECTED_SERVICES = {
    "/app/kv_store.py": b'''import socket\nimport time\n\ntime.sleep(3)\ns = socket.socket(socket.AF_INET, socket.SOCK_STREAM)\ns.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\ns.bind(('127.0.0.1', 8001))\ns.listen(5)\n\nwhile True:\n    conn, addr = s.accept()\n    data = conn.recv(1024)\n    if b'PING' in data:\n        conn.sendall(b'PONG\\n')\n    conn.close()\n''',
    "/app/backend.py": b'''import socket\nimport sys\nfrom http.server import BaseHTTPRequestHandler, HTTPServer\nimport json\n\n# Check KV store\ntry:\n    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)\n    s.connect(('127.0.0.1', 8001))\n    s.close()\nexcept ConnectionRefusedError:\n    sys.exit(1)\n\nclass RequestHandler(BaseHTTPRequestHandler):\n    def do_GET(self):\n        self.send_response(200)\n        self.send_header('Content-type', 'application/json')\n        self.end_headers()\n        self.wfile.write(json.dumps({"data": "success"}).encode())\n\nserver = HTTPServer(('127.0.0.1', 8002), RequestHandler)\nserver.serve_forever()\n''',
    "/app/frontend.py": b'''import urllib.request\nfrom http.server import BaseHTTPRequestHandler, HTTPServer\n\nclass RequestHandler(BaseHTTPRequestHandler):\n    def do_GET(self):\n        try:\n            req = urllib.request.urlopen('http://127.0.0.1:8002' + self.path)\n            data = req.read()\n            self.send_response(200)\n            self.send_header('Content-type', 'application/json')\n            self.end_headers()\n            self.wfile.write(data)\n        except Exception:\n            self.send_response(502)\n            self.end_headers()\n\nserver = HTTPServer(('127.0.0.1', 8003), RequestHandler)\nserver.serve_forever()\n''',
}


def kill_services():
    me = os.getpid()
    for path in SERVICE_PATHS:
        result = subprocess.run(["pgrep", "-f", path], capture_output=True, text=True)
        for value in result.stdout.split():
            try:
                pid = int(value)
                if pid != me:
                    os.kill(pid, signal.SIGTERM)
            except (ValueError, ProcessLookupError, PermissionError):
                pass
    deadline = time.time() + 3
    while time.time() < deadline:
        if all(not port_open(port) for port in (8001, 8002, 8003)):
            return
        time.sleep(0.05)


def port_open(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.1):
            return True
    except OSError:
        return False


def run_start_all(timeout=20):
    result = subprocess.run(
        ["/app/start_all.sh"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout,
    )
    assert result.returncode == 0, "/app/start_all.sh exited unsuccessfully"


def wait_for_ports(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if all(port_open(port) for port in (8001, 8002, 8003)):
            return
        time.sleep(0.05)
    pytest.fail("Services did not become available on ports 8001, 8002, and 8003")


def test_start_all_script_itself_enforces_health_ordering():
    script_path = "/app/start_all.sh"
    assert os.path.isfile(script_path), f"Startup script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Startup script is not executable: {script_path}"

    # The supplied Python services are read-only task inputs and must not be changed.
    for path, expected in EXPECTED_SERVICES.items():
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"Service file was modified contrary to the instruction: {path}"

    kill_services()
    originals = {}
    event_log = "/tmp/startup_probe_events.log"
    try:
        try:
            os.unlink(event_log)
        except FileNotFoundError:
            pass

        for path in SERVICE_PATHS:
            with open(path, "rb") as f:
                originals[path] = f.read()

        common = '''import os, socket, sys, time\nLOG = "/tmp/startup_probe_events.log"\ndef log(message):\n    with open(LOG, "a") as f:\n        f.write(message + "\\n")\n        f.flush()\ndef dependency(port):\n    try:\n        with socket.create_connection(("127.0.0.1", port), timeout=0.25):\n            return True\n    except OSError:\n        return False\ndef serve(name, port, delay):\n    time.sleep(delay)\n    s = socket.socket()\n    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\n    s.bind(("127.0.0.1", port))\n    s.listen(20)\n    log(name + ":listening")\n    while True:\n        conn, _ = s.accept()\n        try:\n            data = conn.recv(4096)\n            if b"PING" in data:\n                conn.sendall(b"PONG\\n")\n            elif data:\n                conn.sendall(b"HTTP/1.0 200 OK\\r\\nContent-Type: application/json\\r\\nContent-Length: 19\\r\\n\\r\\n{\\"data\\": \\"success\\"}")\n        except OSError:\n            pass\n        finally:\n            conn.close()\n'''
        probes = {
            "/app/kv_store.py": common + '''log("kv:start")\nserve("kv", 8001, 0.8)\n''',
            "/app/backend.py": common + '''log("backend:start")\nif not dependency(8001):\n    log("backend:dependency-missing")\n    sys.exit(41)\nlog("backend:dependency-ok")\nserve("backend", 8002, 0.8)\n''',
            "/app/frontend.py": common + '''log("frontend:start")\nif not dependency(8002):\n    log("frontend:dependency-missing")\n    sys.exit(42)\nlog("frontend:dependency-ok")\nserve("frontend", 8003, 0.0)\n''',
        }
        for path, source in probes.items():
            with open(path, "w") as f:
                f.write(source)

        run_start_all(timeout=12)
        wait_for_ports(timeout=4)

        with open(event_log) as f:
            events = [line.strip() for line in f if line.strip()]

        assert "backend:dependency-missing" not in events, "Backend was launched before KV port 8001 was healthy"
        assert "frontend:dependency-missing" not in events, "Frontend was launched before backend port 8002 was healthy"
        required = [
            "kv:start", "kv:listening", "backend:start", "backend:dependency-ok",
            "backend:listening", "frontend:start", "frontend:dependency-ok", "frontend:listening",
        ]
        for event in required:
            assert event in events, f"Missing startup event {event!r}; got {events!r}"
        assert events.index("kv:listening") < events.index("backend:start")
        assert events.index("backend:listening") < events.index("frontend:start")

        # The startup command must return while all three background processes remain alive.
        for svc in SERVICES:
            result = subprocess.run(["pgrep", "-f", svc], capture_output=True, text=True)
            assert result.returncode == 0, f"Service {svc} did not remain running after start_all.sh returned"
    finally:
        kill_services()
        for path, content in originals.items():
            with open(path, "wb") as f:
                f.write(content)

    # Execute the submitted startup script against the real services from a clean state.
    run_start_all(timeout=20)
    wait_for_ports(timeout=8)


def test_processes_running():
    # Check if the three python services are running
    services = ["kv_store.py", "backend.py", "frontend.py"]
    for svc in services:
        result = subprocess.run(["pgrep", "-f", svc], capture_output=True, text=True)
        assert result.returncode == 0, f"Service {svc} is not running."


def test_kv_store_tcp():
    # Multi-protocol Check 1: Raw TCP
    try:
        with socket.create_connection(("127.0.0.1", 8001), timeout=5) as s:
            s.sendall(b"PING\n")
            data = s.recv(1024)
            assert b"PONG" in data, f"Expected PONG from kv_store, got {data!r}"
    except Exception as e:
        pytest.fail(f"Failed to connect to kv_store on port 8001 or receive response: {e}")


def test_frontend_http():
    # Multi-protocol Check 2: HTTP
    try:
        response = requests.get("http://127.0.0.1:8003/api/data", timeout=5)
        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
        data = response.json()
        assert data.get("data") == "success", f"Expected {{'data': 'success'}}, got {data}"
    except Exception as e:
        pytest.fail(f"Failed to fetch from frontend on port 8003: {e}")


def test_health_monitor_script():
    script_path = "/home/user/health_monitor.py"
    log_path = "/home/user/status.log"

    assert os.path.isfile(script_path), f"Health monitor script not found at {script_path}"

    # Run the script to ensure it generates the log
    result = subprocess.run(["python3", script_path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Running {script_path} failed with error: {result.stderr}"

    assert os.path.isfile(log_path), f"Log file not found at {log_path} after running the script"

    with open(log_path, "r") as f:
        content = f.read()

    try:
        log_json = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"Content of {log_path} is not valid JSON: {content}")

    assert log_json.get("data") == "success", f"Expected {{'data': 'success'}} in {log_path}, got {log_json}"


def test_health_monitor_fetches_and_preserves_exact_response():
    script_path = "/home/user/health_monitor.py"
    log_path = "/home/user/status.log"
    payload = ('{  "verification_nonce" : "' + os.urandom(16).hex() +
               '", "data" : "not-a-constant", "items" : [1, 2, 3] }\n')
    seen = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            seen.append((self.command, self.path))
            body = payload.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    kill_services()
    server = HTTPServer(("127.0.0.1", 8003), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass
        result = subprocess.run(["python3", script_path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Running {script_path} failed with error: {result.stderr}"
        assert seen == [("GET", "/api/data")], f"Health monitor did not make the required GET request: {seen!r}"
        assert os.path.isfile(log_path), f"Log file not found at {log_path} after running the script"
        with open(log_path, "r") as f:
            content = f.read()
        assert content == payload, "status.log did not preserve the exact HTTP response text"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        run_start_all(timeout=20)
        wait_for_ports(timeout=8)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
