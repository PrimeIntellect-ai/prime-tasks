#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import shlex
import signal
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest


def stop_port_8080():
    """Terminate processes currently listening on TCP port 8080."""
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local_address = fields[1]
                        state = fields[3]
                        if local_address.rsplit(":", 1)[-1].upper() == "1F90" and state == "0A":
                            socket_inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for proc_path in glob.glob("/proc/[0-9]*"):
        try:
            pid = int(proc_path.rsplit("/", 1)[-1])
            if pid == os.getpid():
                continue
            for fd in glob.glob(proc_path + "/fd/*"):
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    victims.add(pid)
        except (OSError, ValueError):
            continue

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in victims:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.25)


def wait_for_ping(timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            req = urllib.request.Request("http://127.0.0.1:8080/ping", method="GET")
            with urllib.request.urlopen(req, timeout=1) as response:
                content = response.read().decode("utf-8").strip()
                if response.getcode() == 200 and "pong" in content:
                    return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"Application did not become healthy after deploy.sh: {last_error}")


def run_deploy():
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/home/user/deploy.sh"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
    )
    assert result.returncode == 0, f"/home/user/deploy.sh exited with status {result.returncode}."
    wait_for_ping()


def script_command(path):
    if os.access(path, os.X_OK):
        return [path]
    if path.endswith(".py"):
        return ["python3", path]
    if path.endswith(".sh"):
        return ["bash", path]
    try:
        with open(path, "r", errors="replace") as f:
            first_line = f.readline().strip()
        if first_line.startswith("#!"):
            return shlex.split(first_line[2:].strip()) + [path]
    except OSError:
        pass
    return ["bash", path]


def execute_health_script(path):
    return subprocess.run(
        ["runuser", "-u", "user", "--"] + script_command(path),
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


class ConfigurableHandler(BaseHTTPRequestHandler):
    status = 200
    body = b"pong"
    requests = []

    def do_GET(self):
        type(self).requests.append(("GET", self.path))
        self.send_response(type(self).status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(type(self).body)))
        self.end_headers()
        self.wfile.write(type(self).body)

    def log_message(self, format, *args):
        pass


def exercise_case(script, status, body, should_log):
    ConfigurableHandler.status = status
    ConfigurableHandler.body = body
    ConfigurableHandler.requests = []
    server = HTTPServer(("127.0.0.1", 8080), ConfigurableHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    log_path = "/home/user/health.log"
    with open(log_path, "w") as f:
        f.write("SENTINEL\n")
    os.chmod(log_path, 0o666)

    try:
        result = execute_health_script(script)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert ConfigurableHandler.requests, (
        f"{script} did not make an HTTP request. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert ("GET", "/ping") in ConfigurableHandler.requests, (
        f"{script} did not perform GET /ping; observed {ConfigurableHandler.requests!r}."
    )

    with open(log_path, "r") as f:
        lines = f.read().splitlines()
    assert "SENTINEL" in lines, f"{script} overwrote health.log instead of appending to it."
    if should_log:
        assert "STATUS: OK" in lines, (
            f"{script} did not append the exact line 'STATUS: OK' for HTTP 200 with body pong."
        )
    else:
        assert "STATUS: OK" not in lines, (
            f"{script} logged success for an unhealthy response (status={status}, body={body!r})."
        )


def test_symlink_fixed():
    symlink_path = "/home/user/app/data"
    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symlink."
    target = os.readlink(symlink_path)
    assert target == "/home/user/shared_data", f"Symlink {symlink_path} points to {target}, expected /home/user/shared_data."


def test_deploy_script_starts_application():
    stop_port_8080()
    try:
        os.remove("/home/user/app/ping")
    except FileNotFoundError:
        pass
    run_deploy()


def test_app_running():
    url = "http://127.0.0.1:8080/ping"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.getcode()
            content = response.read().decode("utf-8").strip()
            assert status == 200, f"Expected HTTP 200 OK, got {status}."
            assert "pong" in content, f"Expected 'pong' in response, got '{content}'."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the application at {url}: {e}")


def test_health_log():
    log_path = "/home/user/health.log"
    assert os.path.isfile(log_path), f"Health log file {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read()
    assert "STATUS: OK" in content, f"Expected 'STATUS: OK' in {log_path}, but it was not found."


def test_health_check_script_exists():
    scripts = glob.glob("/home/user/health_check*")
    assert len(scripts) > 0, "Health check script starting with '/home/user/health_check' is missing."
    valid_scripts = [s for s in scripts if os.path.isfile(s)]
    assert len(valid_scripts) > 0, "Health check script must be a valid file."


def test_health_check_script_behavior():
    scripts = [s for s in glob.glob("/home/user/health_check*") if os.path.isfile(s)]
    stop_port_8080()
    failures = []
    passing_script = None
    try:
        for script in scripts:
            try:
                exercise_case(script, 200, b"not pong", False)
                exercise_case(script, 503, b"pong", False)
                exercise_case(script, 200, b"pong", True)
                passing_script = script
                break
            except Exception as exc:
                failures.append(f"{script}: {exc}")
        assert passing_script is not None, "No health-check script met the required behavior:\n" + "\n".join(failures)
    finally:
        stop_port_8080()
        run_deploy()


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
