#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

URL = "http://127.0.0.1:8080/"
EXPECTED = 'HEALTHY: {"status": "healthy", "service": "backend"}'


def fetch(url, timeout=2):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.getcode(), response.read().decode("utf-8")


def listening_inodes(port):
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def socket_owner_pids(port):
    wanted = {f"socket:[{inode}]" for inode in listening_inodes(port)}
    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") in wanted:
                        owners.add(int(name))
                        break
                except (FileNotFoundError, PermissionError):
                    continue
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except FileNotFoundError:
        return ""


def ppid(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            return int(f.read().split()[3])
    except (FileNotFoundError, ValueError, IndexError):
        return 0


def process_or_ancestor_matches(pid, required):
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        text = cmdline(pid)
        if all(item in text for item in required):
            return True
        pid = ppid(pid)
    return False


def wait_for_port_free(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket() as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                s.bind(("127.0.0.1", port))
                return
            except OSError:
                time.sleep(0.05)
    pytest.fail(f"Port {port} did not become free")


def wait_for_healthy(timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            status, body = fetch(URL, timeout=0.5)
            if status == 200:
                return body
        except Exception as exc:
            last_error = exc
        time.sleep(0.05)
    pytest.fail(f"Service did not become healthy: {last_error}")


def test_nginx_conf_fixed():
    conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} is missing"
    with open(conf_path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:9000;" in content, "nginx.conf does not contain the corrected proxy_pass to port 9000"


def test_health_log_content():
    log_path = "/home/user/health.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing. Did you run monitor.py?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED, f"health.log content is incorrect. Expected '{EXPECTED}', got '{content}'"


def test_monitor_script_exists():
    script_path = "/home/user/monitor.py"
    assert os.path.isfile(script_path), f"File {script_path} is missing"


def test_services_running_and_responding():
    try:
        status, body = fetch(URL)
    except Exception as e:
        pytest.fail(f"Failed to connect to {URL} - {e}")

    assert status == 200, f"Expected status code 200, got {status}. Is ENV_MODE=production set?"
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        pytest.fail("Response body is not valid JSON")
    assert data.get("status") == "healthy", "JSON response does not contain expected status"
    assert data.get("service") == "backend", "JSON response does not contain expected service"


def test_expected_processes_own_the_service_ports():
    nginx_owners = socket_owner_pids(8080)
    assert nginx_owners, "No process is listening on port 8080"
    assert any(process_or_ancestor_matches(pid, ["nginx", "/home/user/nginx/nginx.conf"])
               for pid in nginx_owners), "Port 8080 is not owned by the configured Nginx process"

    backend_owners = socket_owner_pids(9000)
    assert backend_owners, "No process is listening on backend port 9000"
    backend_pids = [pid for pid in backend_owners if "/home/user/app/backend.py" in cmdline(pid)]
    assert backend_pids, "Port 9000 is not owned by the supplied backend.py process"
    assert any(b"ENV_MODE=production" in open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
               for pid in backend_pids), "The backend was not started with ENV_MODE=production"

    status, body = fetch("http://127.0.0.1:9000/")
    assert status == 200
    assert json.loads(body) == {"status": "healthy", "service": "backend"}


def test_monitor_is_executed_and_logs_live_success_response():
    status, body = fetch(URL)
    assert status == 200
    log_path = "/home/user/health.log"
    if os.path.exists(log_path):
        os.unlink(log_path)

    result = subprocess.run(
        ["python3", "/home/user/monitor.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"monitor.py failed: {result.stderr}"
    assert os.path.isfile(log_path), "monitor.py did not create health.log"
    with open(log_path) as f:
        actual = f.read().strip()
    assert actual == "HEALTHY: " + body, "monitor.py did not log the live HTTP response body"
    assert actual == EXPECTED


def test_monitor_writes_nothing_for_non_200_response():
    pid_path = "/home/user/nginx/nginx.pid"
    assert os.path.isfile(pid_path), "Nginx PID file is missing"
    with open(pid_path) as f:
        nginx_pid = int(f.read().strip())

    fake = None
    restarted = None
    try:
        os.kill(nginx_pid, signal.SIGTERM)
        deadline = time.time() + 5
        while time.time() < deadline and os.path.exists(f"/proc/{nginx_pid}"):
            time.sleep(0.05)
        wait_for_port_free(8080)

        fake_code = r'''from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(503)
        self.end_headers()
        self.wfile.write(b"temporary-unhealthy-response")
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 8080), H).serve_forever()
'''
        fake = subprocess.Popen(["python3", "-c", fake_code], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                fetch(URL, timeout=0.3)
            except urllib.error.HTTPError as exc:
                if exc.code == 503:
                    break
            except Exception:
                pass
            time.sleep(0.05)
        else:
            pytest.fail("Could not start temporary non-200 HTTP endpoint")

        log_path = "/home/user/health.log"
        if os.path.exists(log_path):
            os.unlink(log_path)
        subprocess.run(["python3", "/home/user/monitor.py"], stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=5)
        assert not os.path.exists(log_path) or os.path.getsize(log_path) == 0, \
            "monitor.py wrote health output for a non-200 response"
    finally:
        if fake is not None and fake.poll() is None:
            fake.terminate()
            try:
                fake.wait(timeout=3)
            except subprocess.TimeoutExpired:
                fake.kill()
                fake.wait()
        wait_for_port_free(8080)
        restarted = subprocess.Popen(
            ["nginx", "-c", "/home/user/nginx/nginx.conf"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_for_healthy()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
