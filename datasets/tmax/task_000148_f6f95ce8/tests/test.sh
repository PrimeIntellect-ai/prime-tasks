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
import signal
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
import requests

PORT = 8443
EXPECTED_EXE = "/app/telemetry_gateway"
EXPECTED_ENV = {
    "GATEWAY_PORT": "8443",
    "GATEWAY_TOKEN": "admin-secret-991",
    "GATEWAY_DATA_DIR": "/home/user/gateway_data",
}
_launched_wrappers = []


def _tcp4_listeners():
    listeners = []
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, port_hex = fields[1].split(":")
            if int(port_hex, 16) == PORT and fields[3] == "0A":
                listeners.append((address, fields[9]))
    return listeners


def _tcp6_listeners():
    listeners = []
    with open("/proc/net/tcp6", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, port_hex = fields[1].split(":")
            if int(port_hex, 16) == PORT and fields[3] == "0A":
                listeners.append((address, fields[9]))
    return listeners


def _owners_for_inodes(inodes):
    owners = set()
    wanted = {f"socket:[{inode}]" for inode in inodes}
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
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def _listener_pids(require_exact_bind=True):
    tcp4 = _tcp4_listeners()
    tcp6 = _tcp6_listeners()
    if require_exact_bind:
        assert tcp4, "Nothing is listening on IPv4 port 8443"
        assert not tcp6, "Port 8443 must not also be bound on IPv6"
        assert all(address == "0100007F" for address, _ in tcp4), \
            "The service must bind exactly to 127.0.0.1:8443"
    return _owners_for_inodes([inode for _, inode in tcp4] +
                              [inode for _, inode in tcp6])


def _read_environ(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    env = {}
    for entry in entries:
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            env[key.decode(errors="replace")] = value.decode(errors="replace")
    return env


def _assert_real_gateway_running():
    pids = _listener_pids()
    assert pids, "Could not identify the process listening on port 8443"
    assert len(pids) == 1, f"Expected one listener process, found {sorted(pids)}"
    pid = next(iter(pids))
    exe = os.readlink(f"/proc/{pid}/exe")
    assert exe == EXPECTED_EXE, \
        f"Port 8443 is served by {exe}, not {EXPECTED_EXE}"

    env = _read_environ(pid)
    for key, expected in EXPECTED_ENV.items():
        assert env.get(key) == expected, \
            f"Running gateway has incorrect {key}: {env.get(key)!r}"

    path = env.get("PATH", "")
    curl_found = any(
        os.path.isfile(os.path.join(directory, "curl")) and
        os.access(os.path.join(directory, "curl"), os.X_OK)
        for directory in path.split(os.pathsep) if directory
    )
    assert curl_found, "Running gateway's PATH cannot resolve curl"
    return pid


def _kill_port_listener():
    pids = _listener_pids(require_exact_bind=False)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and (_tcp4_listeners() or _tcp6_listeners()):
        time.sleep(0.05)
    if _tcp4_listeners() or _tcp6_listeners():
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        deadline = time.time() + 2
        while time.time() < deadline and (_tcp4_listeners() or _tcp6_listeners()):
            time.sleep(0.05)
    assert not _tcp4_listeners() and not _tcp6_listeners(), \
        "Could not free port 8443 before testing the wrapper"


def _launch_wrapper_and_wait():
    stripped_env = {
        "HOME": "/home/user",
        "USER": "user",
        "LOGNAME": "user",
        "SHELL": "/bin/bash",
        "PATH": "/opt/custom_empty_bin",
    }
    proc = subprocess.Popen(
        ["/bin/bash", "/home/user/start_service.sh"],
        cwd="/home/user",
        env=stripped_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    _launched_wrappers.append(proc)
    deadline = time.time() + 6
    last_error = None
    while time.time() < deadline:
        try:
            return _assert_real_gateway_running()
        except (AssertionError, FileNotFoundError, ProcessLookupError) as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"start_service.sh did not launch the real gateway correctly: {last_error}")


def setup_module(module):
    wrapper = "/home/user/start_service.sh"
    assert os.path.exists(wrapper), f"Wrapper script {wrapper} does not exist"
    assert os.path.isfile(wrapper), f"{wrapper} is not a file"
    assert os.access(wrapper, os.X_OK), f"{wrapper} is not executable"
    with open(wrapper, "rb") as f:
        first_line = f.readline().decode(errors="replace").strip()
    assert first_line in ("#!/bin/bash", "#!/usr/bin/bash", "#!/usr/bin/env bash"), \
        "start_service.sh must be a Bash script"

    # The agent must already have left the genuine daemon running.
    _assert_real_gateway_running()

    # Then prove the submitted wrapper itself can recreate that state from a
    # cron-like stripped environment rather than relying on the existing process.
    _kill_port_listener()
    _launch_wrapper_and_wait()


def test_gateway_data_dir_exists():
    data_dir = "/home/user/gateway_data"
    assert os.path.exists(data_dir), f"Directory {data_dir} does not exist."
    assert os.path.isdir(data_dir), f"{data_dir} is not a directory."


def test_health_check_script_exists_and_runs():
    script_path = "/home/user/health_check.sh"
    assert os.path.exists(script_path), f"Health check script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    # Preserve the original check against the genuine daemon.
    result = subprocess.run([script_path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Health check script failed with exit code {result.returncode}.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    # Exercise the health check independently and record what it actually sends.
    _kill_port_listener()

    class RecordingHandler(BaseHTTPRequestHandler):
        requests_seen = []
        response_code = 200

        def do_GET(self):
            type(self).requests_seen.append((self.path, self.headers.get("Authorization")))
            self.send_response(type(self).response_code)
            self.end_headers()
            self.wfile.write(b"OK" if type(self).response_code == 200 else b"failure")

        def log_message(self, format, *args):
            pass

    server = HTTPServer(("127.0.0.1", PORT), RecordingHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = subprocess.run([script_path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, "Health check must exit 0 for a successful authenticated response"
        assert RecordingHandler.requests_seen, "Health check did not make an HTTP request"
        assert RecordingHandler.requests_seen[-1] == ("/status", "Bearer admin-secret-991"), \
            f"Health check sent the wrong path or authentication header: {RecordingHandler.requests_seen[-1]!r}"

        RecordingHandler.response_code = 503
        result = subprocess.run([script_path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 1, \
            f"Health check must exit 1 when the endpoint fails, got {result.returncode}"
    finally:
        server.shutdown()
        thread.join(timeout=2)
        server.server_close()

    # Restore the required final state using the submitted wrapper.
    _launch_wrapper_and_wait()


def test_telemetry_gateway_http_endpoint():
    _assert_real_gateway_running()
    url = "http://127.0.0.1:8443/status"
    headers = {"Authorization": "Bearer admin-secret-991"}

    max_retries = 3
    response = None
    for attempt in range(max_retries):
        try:
            response = requests.get(url, headers=headers, timeout=2)
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException:
            if attempt == max_retries - 1:
                pytest.fail(f"Failed to connect to {url} after {max_retries} attempts. Is the service running and bound to 127.0.0.1:8443?")
            time.sleep(1)

    assert response is not None
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text}"
    assert response.text == "OK", f"Expected gateway response body OK, got {response.text!r}"

    missing = requests.get(url, timeout=2)
    wrong = requests.get(url, headers={"Authorization": "Bearer wrong-token"}, timeout=2)
    assert missing.status_code == 401, f"Missing authentication should return 401, got {missing.status_code}"
    assert wrong.status_code == 401, f"Incorrect authentication should return 401, got {wrong.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
