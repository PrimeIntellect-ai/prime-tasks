#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.server
import os
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

HOME = Path("/home/user")
SOURCE = HOME / "iot-source"
BARE = HOME / "iot-hub.git"
DEPLOY = HOME / "iot-deploy"
LOG = HOME / "deployment_log.txt"
PID_FILE = HOME / "edge_service.pid"


def git(repo, *args):
    return subprocess.check_output(
        ["git", "-c", f"safe.directory={repo}", "-C", str(repo), *args],
        stderr=subprocess.STDOUT,
    ).decode().strip()


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def fetch_ping(port, timeout=2):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/ping", timeout=timeout) as response:
        return response.status, response.read().decode("utf-8").strip()


def wait_for_ping(port, seconds=6):
    deadline = time.time() + seconds
    last_error = None
    while time.time() < deadline:
        try:
            return fetch_ping(port, timeout=0.5)
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Service on port {port} did not become ready: {last_error}")


def read_pid():
    assert PID_FILE.is_file(), f"{PID_FILE} does not exist."
    value = PID_FILE.read_text().strip()
    assert value.isdigit(), f"PID file does not contain a valid integer: '{value}'"
    return int(value)


def terminate_pid_from_file():
    if not PID_FILE.is_file():
        return
    value = PID_FILE.read_text().strip()
    if not value.isdigit():
        return
    pid = int(value)
    try:
        os.kill(pid, 15)
    except ProcessLookupError:
        return
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    try:
        os.kill(pid, 9)
    except ProcessLookupError:
        pass


def test_bashrc_contains_env_vars():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist."
    with open(bashrc_path, "r") as f:
        content = f.read()
    assert "EDGE_DEVICE_ID=edge-node-42" in content, "EDGE_DEVICE_ID=edge-node-42 not found in .bashrc"
    assert "EDGE_PORT=8484" in content, "EDGE_PORT=8484 not found in .bashrc"


def test_bare_git_repo_exists():
    git_dir = "/home/user/iot-hub.git"
    assert os.path.isdir(git_dir), f"{git_dir} directory does not exist."
    config_path = os.path.join(git_dir, "config")
    assert os.path.isfile(config_path), f"Git config not found at {config_path}. Is it a valid bare repo?"
    with open(config_path, "r") as f:
        content = f.read()
    assert "bare = true" in content.lower(), "Repository is not configured as bare."


def test_deployment_log_success():
    assert LOG.is_file(), f"{LOG} does not exist."
    content = LOG.read_text()
    assert "[edge-node-42] DEPLOYMENT_SUCCESS" in content, "Deployment success message not found in log."


def test_http_server_ping():
    url = "http://127.0.0.1:8484/ping"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            body = response.read().decode("utf-8").strip()
            assert body == "pong", f"Expected body 'pong', got '{body}'"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to {url}: {e}"


def test_pid_file_and_process():
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running."


def test_source_repository_commit_remote_and_deployment():
    assert (SOURCE / ".git").is_dir(), "/home/user/iot-source is not a Git repository"
    assert (SOURCE / "edge_service.py").is_file(), "edge_service.py is missing from iot-source"
    assert (HOME / "health_monitor.py").is_file(), "health_monitor.py is missing"
    assert DEPLOY.is_dir(), "/home/user/iot-deploy is missing"

    assert git(SOURCE, "symbolic-ref", "--short", "HEAD") == "master", "iot-source is not on master"
    head = git(SOURCE, "rev-parse", "HEAD")
    committed_service = subprocess.check_output(
        ["git", "-c", f"safe.directory={SOURCE}", "-C", str(SOURCE), "show", "HEAD:edge_service.py"]
    )
    assert committed_service == (SOURCE / "edge_service.py").read_bytes(), "edge_service.py is not committed at HEAD"

    remotes = git(SOURCE, "remote").splitlines()
    assert "local" in remotes, "Remote named local is missing"
    remote_master = git(SOURCE, "ls-remote", "local", "refs/heads/master").split()
    assert remote_master and remote_master[0] == head, "master has not been pushed to the local remote"
    assert git(BARE, "rev-parse", "refs/heads/master") == head, "Bare repository master differs from source master"

    deployed_service = DEPLOY / "edge_service.py"
    assert deployed_service.is_file(), "edge_service.py was not checked out into iot-deploy"
    assert deployed_service.read_bytes() == committed_service, "Deployed edge_service.py differs from committed code"

    hook = BARE / "hooks" / "post-receive"
    assert hook.is_file(), "post-receive hook is missing"
    assert os.access(hook, os.X_OK), "post-receive hook is not executable"


def test_edge_service_uses_dynamic_port_and_detaches():
    terminate_pid_from_file()
    port = free_port()
    env = os.environ.copy()
    env["EDGE_PORT"] = str(port)

    started = time.time()
    subprocess.run(
        ["python3", str(SOURCE / "edge_service.py")],
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
        check=True,
    )
    assert time.time() - started < 5, "edge_service.py did not detach promptly"
    assert wait_for_ping(port) == (200, "pong")
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"PID {pid} written by edge_service.py is not running"
    terminate_pid_from_file()


class PingHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/ping":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"pong")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass


def test_health_monitor_reads_environment_retries_and_logs_exact_success():
    port = free_port()
    device = "verifier-" + uuid.uuid4().hex
    before = LOG.read_text().splitlines() if LOG.exists() else []

    def delayed_server():
        time.sleep(0.35)
        server = http.server.HTTPServer(("127.0.0.1", port), PingHandler)
        server.timeout = 6
        server.handle_request()
        server.server_close()

    thread = threading.Thread(target=delayed_server, daemon=True)
    thread.start()
    env = os.environ.copy()
    env["EDGE_DEVICE_ID"] = device
    env["EDGE_PORT"] = str(port)
    subprocess.run(
        ["python3", str(HOME / "health_monitor.py")],
        env=env,
        timeout=8,
        check=True,
    )
    thread.join(timeout=2)
    after = LOG.read_text().splitlines()
    assert len(after) > len(before), "health_monitor.py did not append to deployment_log.txt"
    assert after[len(before):] == [f"[{device}] DEPLOYMENT_SUCCESS"], "Health monitor did not append the exact success line"


def test_post_receive_hook_performs_real_deployment_pipeline():
    terminate_pid_from_file()
    try:
        fetch_ping(8484, timeout=0.3)
        assert False, "Port 8484 remained served after terminating the PID from edge_service.pid"
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        pass

    marker_name = ".verifier-deploy-" + uuid.uuid4().hex
    marker_value = uuid.uuid4().hex
    marker = SOURCE / marker_name
    marker.write_text(marker_value + "\n")
    subprocess.check_call([
        "git", "-c", f"safe.directory={SOURCE}", "-C", str(SOURCE),
        "-c", "user.name=Verifier", "-c", "user.email=verifier@localhost",
        "add", marker_name,
    ])
    subprocess.check_call([
        "git", "-c", f"safe.directory={SOURCE}", "-C", str(SOURCE),
        "-c", "user.name=Verifier", "-c", "user.email=verifier@localhost",
        "commit", "-m", "Verifier deployment trigger",
    ], stdout=subprocess.DEVNULL)

    before_lines = LOG.read_text().splitlines() if LOG.exists() else []
    subprocess.check_call([
        "git", "-c", f"safe.directory={SOURCE}", "-C", str(SOURCE),
        "push", "local", "master",
    ], stdout=subprocess.DEVNULL)

    new_head = git(SOURCE, "rev-parse", "HEAD")
    assert git(BARE, "rev-parse", "refs/heads/master") == new_head, "Push did not update bare master"
    deployed_marker = DEPLOY / marker_name
    assert deployed_marker.is_file(), "post-receive hook did not check out newly pushed content"
    assert deployed_marker.read_text() == marker_value + "\n", "Deployed checkout has incorrect pushed content"

    assert wait_for_ping(8484, seconds=7) == (200, "pong"), "Hook did not start edge_service.py"
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Hook-created service PID {pid} is not running"

    after_lines = LOG.read_text().splitlines()
    appended = after_lines[len(before_lines):]
    assert "[edge-node-42] DEPLOYMENT_SUCCESS" in appended, "Hook did not run health_monitor.py successfully"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
