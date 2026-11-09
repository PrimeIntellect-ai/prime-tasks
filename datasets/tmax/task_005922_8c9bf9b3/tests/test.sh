#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest


def test_backends_list_exists_and_content():
    """Verify /home/user/lb/backends.list exists and has the correct contents."""
    filepath = "/home/user/lb/backends.list"
    assert os.path.isfile(filepath), f"{filepath} does not exist."
    with open(filepath, "r") as f:
        content = f.read().strip()

    expected_content = (
        "server backend_A 127.0.0.1:8001\n"
        "server backend_B 127.0.0.1:8002\n"
        "server backend_C 127.0.0.1:8003"
    )
    assert content == expected_content, f"Contents of {filepath} do not match the expected setup."


def test_ports_listening():
    """Verify that ports 8001 and 8003 are listening, and 8002 is not."""
    def is_port_open(port):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            return s.connect_ex(('127.0.0.1', port)) == 0

    assert is_port_open(8001), "Port 8001 is not listening (backend_A)."
    assert not is_port_open(8002), "Port 8002 is listening, but it should be dead (backend_B)."
    assert is_port_open(8003), "Port 8003 is not listening (backend_C)."


def test_monitor_script_executable():
    """Verify /home/user/lb/monitor.sh exists and is executable."""
    filepath = "/home/user/lb/monitor.sh"
    assert os.path.isfile(filepath), f"{filepath} does not exist."
    assert os.access(filepath, os.X_OK), f"{filepath} is not executable."


def test_active_list_content():
    """Verify /home/user/lb/active.list has the expected contents."""
    filepath = "/home/user/lb/active.list"
    assert os.path.isfile(filepath), f"{filepath} does not exist. Did you run the script?"
    with open(filepath, "r") as f:
        content = f.read().strip()

    expected_content = (
        "server backend_A 127.0.0.1:8001\n"
        "# server backend_B 127.0.0.1:8002\n"
        "server backend_C 127.0.0.1:8003"
    )
    assert content == expected_content, f"Contents of {filepath} do not match the expected output."


def test_health_log_content():
    """Verify /home/user/lb/health.log has the expected error string."""
    filepath = "/home/user/lb/health.log"
    assert os.path.isfile(filepath), f"{filepath} does not exist. Did you run the script?"
    with open(filepath, "r") as f:
        content = f.read().strip()

    expected_error = "ERROR: backend_B on 127.0.0.1:8002 is unreachable"
    assert expected_error in content, f"Expected error not found in {filepath}."


class QuietHandler(BaseHTTPRequestHandler):
    status = 200
    delay = 0

    def do_GET(self):
        if self.delay:
            time.sleep(self.delay)
        self.send_response(self.status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, format, *args):
        pass


def make_handler(status, delay=0):
    return type(
        f"Handler_{status}_{delay}",
        (QuietHandler,),
        {"status": status, "delay": delay},
    )


def start_server(status, delay=0):
    server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(status, delay))
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, server.server_address[1]


def unused_port():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def test_monitor_executes_and_reacts_to_runtime_backend_states():
    """Execute the submitted monitor against unpredictable live backend states."""
    paths = [
        "/home/user/lb/backends.list",
        "/home/user/lb/active.list",
        "/home/user/lb/health.log",
    ]
    saved = {path: open(path, "rb").read() for path in paths}

    good_server, good_port = start_server(200)
    bad_server, bad_port = start_server(503)
    # This endpoint eventually returns 200, but only after the required one-second
    # maximum timeout has expired.
    slow_server, slow_port = start_server(200, delay=1.5)
    dead_port = unused_port()

    token = secrets.token_hex(6)
    good_name = f"live_{token}"
    bad_name = f"error_{token}"
    slow_name = f"slow_{token}"
    dead_name = f"dead_{token}"
    lines = [
        f"server {good_name} 127.0.0.1:{good_port}",
        f"server {bad_name} 127.0.0.1:{bad_port}",
        f"server {slow_name} 127.0.0.1:{slow_port}",
        f"server {dead_name} 127.0.0.1:{dead_port}",
    ]

    try:
        with open("/home/user/lb/backends.list", "w") as f:
            f.write("\n".join(lines) + "\n")
        open("/home/user/lb/active.list", "w").close()
        open("/home/user/lb/health.log", "w").close()

        result = subprocess.run(
            ["/home/user/lb/monitor.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=6,
        )
        assert result.returncode == 0, (
            f"monitor.sh exited with {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

        with open("/home/user/lb/active.list", "r") as f:
            active = f.read().strip()
        expected_active = "\n".join([
            lines[0],
            "# " + lines[1],
            "# " + lines[2],
            "# " + lines[3],
        ])
        assert active == expected_active, "monitor.sh did not derive active.list from live HTTP results"

        with open("/home/user/lb/health.log", "r") as f:
            health = f.read().strip()
        expected_health = "\n".join([
            f"ERROR: {bad_name} on 127.0.0.1:{bad_port} is unreachable",
            f"ERROR: {slow_name} on 127.0.0.1:{slow_port} is unreachable",
            f"ERROR: {dead_name} on 127.0.0.1:{dead_port} is unreachable",
        ])
        assert health == expected_health, "monitor.sh did not log each dynamically unreachable backend correctly"
    finally:
        for server in (good_server, bad_server, slow_server):
            server.shutdown()
            server.server_close()
        for path, data in saved.items():
            with open(path, "wb") as f:
                f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
