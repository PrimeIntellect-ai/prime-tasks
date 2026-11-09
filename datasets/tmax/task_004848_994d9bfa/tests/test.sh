#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import time
import uuid
import signal

import pytest
import requests

EXPECTED_SERVER = r'''import argparse
import threading
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--host', required=True)
parser.add_argument('--http', type=int, required=True)
parser.add_argument('--tcp', type=int, required=True)
args = parser.parse_args()

if not args.host:
    print("Error: --host cannot be empty")
    sys.exit(1)

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "healthy"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

def run_http():
    try:
        server = HTTPServer((args.host, args.http), HealthHandler)
        server.serve_forever()
    except Exception as e:
        print(f"HTTP Server error: {e}")

def run_tcp():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((args.host, args.tcp))
        s.listen()
        while True:
            conn, addr = s.accept()
            data = conn.recv(1024)
            if b'PING' in data:
                conn.sendall(b'PONG\n')
            conn.close()
    except Exception as e:
        print(f"TCP Server error: {e}")

t1 = threading.Thread(target=run_http, daemon=True)
t2 = threading.Thread(target=run_tcp, daemon=True)
t1.start()
t2.start()

t1.join()
t2.join()
'''.encode()

START_MARKER = "/tmp/edge-telemetry-started-" + uuid.uuid4().hex
DAEMON_PID = None


def _cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    except (OSError, ValueError):
        return []


def _listening_inodes(port):
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    if state != "0A":
                        continue
                    address, port_hex = local_address.rsplit(":", 1)
                    if int(port_hex, 16) == port:
                        result.add(fields[9])
        except OSError:
            pass
    return result


def _pid_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fd_dir)
    except OSError:
        return result
    for name in names:
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def _kill_old_servers():
    victims = set()
    port_inodes = _listening_inodes(8080) | _listening_inodes(8081)
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        cmd = _cmdline(pid)
        if "/app/edge-telemetry/server.py" in cmd or (_pid_socket_inodes(pid) & port_inodes):
            victims.add(pid)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in victims:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)


def _option_value(cmd, option):
    if option in cmd:
        index = cmd.index(option)
        if index + 1 < len(cmd):
            return cmd[index + 1]
    prefix = option + "="
    for arg in cmd:
        if arg.startswith(prefix):
            return arg[len(prefix):]
    return None


@pytest.fixture(scope="session", autouse=True)
def execute_deployment():
    global DAEMON_PID

    deploy = "/home/user/deploy.sh"
    assert os.path.isfile(deploy), f"{deploy} is missing"
    assert os.access(deploy, os.X_OK), f"{deploy} is not executable"

    server_path = "/app/edge-telemetry/server.py"
    assert os.path.isfile(server_path), f"{server_path} is missing"
    with open(server_path, "rb") as f:
        assert f.read() == EXPECTED_SERVER, "The vendored telemetry daemon was replaced or modified"

    _kill_old_servers()
    subprocess.run(["rm", "-rf", "/home/user/logs"], check=True)

    # Recreate the package's initial typo so deploy.sh must really automate the fix,
    # then record only an execution that occurs after HOST has the correct value.
    start_script = f'''#!/bin/bash
export HOSST="0.0.0.0"
if [ "$HOST" = "0.0.0.0" ]; then : > "{START_MARKER}"; fi
nohup python3 /app/edge-telemetry/server.py --host $HOST --http 8080 --tcp 8081 >> /home/user/logs/telemetry.log 2>&1 &
'''
    with open("/app/edge-telemetry/start.sh", "w") as f:
        f.write(start_script)
    os.chmod("/app/edge-telemetry/start.sh", 0o755)

    try:
        result = subprocess.run(
            [deploy], cwd="/home/user", capture_output=True, text=True, timeout=15
        )
    except subprocess.TimeoutExpired:
        pytest.fail("deploy.sh did not finish within 15 seconds")
    assert result.returncode == 0, (
        f"deploy.sh failed with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(START_MARKER), "deploy.sh did not execute start.sh after fixing HOST"

    deadline = time.time() + 6
    while time.time() < deadline and DAEMON_PID is None:
        inodes_8080 = _listening_inodes(8080)
        inodes_8081 = _listening_inodes(8081)
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            pid = int(name)
            cmd = _cmdline(pid)
            if "/app/edge-telemetry/server.py" not in cmd:
                continue
            if _option_value(cmd, "--host") != "0.0.0.0":
                continue
            if _option_value(cmd, "--http") != "8080" or _option_value(cmd, "--tcp") != "8081":
                continue
            owned = _pid_socket_inodes(pid)
            if owned & inodes_8080 and owned & inodes_8081:
                DAEMON_PID = pid
                break
        if DAEMON_PID is None:
            time.sleep(0.2)

    assert DAEMON_PID is not None, (
        "The vendored server.py process is not listening on both required ports"
    )
    yield


def test_start_script_fixed():
    start_sh_path = "/app/edge-telemetry/start.sh"
    assert os.path.isfile(start_sh_path), f"{start_sh_path} is missing"

    with open(start_sh_path, "r") as f:
        content = f.read()

    # Preserve the original assertion and additionally reject the HOST-text bypass.
    assert "HOSST" not in content or "HOST=" in content, "The typo in start.sh does not appear to be fixed."
    shell_code = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    assert not re.search(r"\bHOSST\s*=", shell_code), "The HOSST typo remains in executable shell code"
    assert re.search(r'(?m)^\s*(?:export\s+)?HOST\s*=\s*["\']?0\.0\.0\.0["\']?\s*$', shell_code), (
        "start.sh does not assign HOST=0.0.0.0"
    )


def test_deploy_script_exists():
    deploy_sh_path = "/home/user/deploy.sh"
    assert os.path.isfile(deploy_sh_path), f"{deploy_sh_path} is missing"
    assert os.access(deploy_sh_path, os.X_OK), f"{deploy_sh_path} is not executable"


def test_logrotate_config():
    logrotate_conf_path = "/home/user/telemetry-logrotate.conf"
    assert os.path.isfile(logrotate_conf_path), f"{logrotate_conf_path} is missing"

    with open(logrotate_conf_path, "r") as f:
        content = f.read()

    assert "/home/user/logs/telemetry.log" in content, "Logrotate config does not target /home/user/logs/telemetry.log"

    keywords = ["daily", "rotate 7", "compress", "missingok", "notifempty"]
    for kw in keywords:
        assert re.search(rf"\b{kw}\b", content), f"Logrotate config missing '{kw}'"

    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    stanza = re.search(
        r'(?ms)^\s*(?:"/home/user/logs/telemetry\.log"|/home/user/logs/telemetry\.log)\s*\{(.*?)^\s*\}',
        uncommented,
    )
    assert stanza, "No real logrotate stanza targets telemetry.log"
    body = stanza.group(1)
    required = {
        "daily": r"(?m)^\s*daily\s*$",
        "rotate 7": r"(?m)^\s*rotate\s+7\s*$",
        "compress": r"(?m)^\s*compress\s*$",
        "missingok": r"(?m)^\s*missingok\s*$",
        "notifempty": r"(?m)^\s*notifempty\s*$",
    }
    for name, pattern in required.items():
        assert re.search(pattern, body), f"Logrotate stanza missing active directive '{name}'"

    result = subprocess.run(["logrotate", "-d", logrotate_conf_path], capture_output=True, text=True)
    assert result.returncode == 0, f"logrotate -d failed: {result.stderr}"


def test_http_health_check():
    url = "http://127.0.0.1:8080/health"
    try:
        response = requests.get(url, timeout=2)
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
        assert response.json() == {"status": "healthy"}, f"Unexpected response body: {response.text}"
        random_path = "/" + uuid.uuid4().hex
        assert requests.get("http://127.0.0.1:8080" + random_path, timeout=2).status_code == 404
    except requests.RequestException as e:
        pytest.fail(f"HTTP health check failed: {e}")


def test_tcp_ping():
    host = "127.0.0.1"
    port = 8081
    try:
        with socket.create_connection((host, port), timeout=2) as s:
            s.sendall(b"PING\n")
            data = s.recv(1024)
            assert data == b"PONG\n", f"Expected 'PONG\\n', got {data!r}"
        with socket.create_connection((host, port), timeout=2) as s:
            s.sendall(("NOPE-" + uuid.uuid4().hex).encode())
            data = s.recv(1024)
            assert data == b"", f"Unexpected response to non-PING input: {data!r}"
    except Exception as e:
        pytest.fail(f"TCP ping failed: {e}")


def test_daemon_identity_binding_and_logging():
    assert DAEMON_PID is not None and os.path.isdir(f"/proc/{DAEMON_PID}"), "Vendored daemon exited"
    cmd = _cmdline(DAEMON_PID)
    assert "/app/edge-telemetry/server.py" in cmd
    assert _option_value(cmd, "--host") == "0.0.0.0"

    for port in (8080, 8081):
        wildcard = False
        for path in ("/proc/net/tcp", "/proc/net/tcp6"):
            try:
                with open(path) as f:
                    next(f)
                    for line in f:
                        fields = line.split()
                        address, port_hex = fields[1].rsplit(":", 1)
                        if fields[3] == "0A" and int(port_hex, 16) == port and set(address) <= {"0"}:
                            if fields[9] in _pid_socket_inodes(DAEMON_PID):
                                wildcard = True
            except OSError:
                pass
        assert wildcard, f"Vendored daemon is not bound to all interfaces on port {port}"

    expected_log = "/home/user/logs/telemetry.log"
    for fd in ("1", "2"):
        target = os.readlink(f"/proc/{DAEMON_PID}/fd/{fd}")
        assert target == expected_log, f"Daemon fd {fd} is not redirected to telemetry.log: {target}"


def test_log_file_exists():
    log_path = "/home/user/logs/telemetry.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
