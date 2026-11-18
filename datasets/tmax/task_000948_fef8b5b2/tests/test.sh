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
import json
import os
import queue
import re
import signal
import socket
import subprocess
import tempfile
import threading
import time
import uuid
import shutil
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
import requests

VENDOR_DIR = "/app/git-notifier-2.0.0"
VENV_DIR = "/home/user/venv"
WRAPPER = "/home/user/start-daemon.sh"
REPO_DIR = "/home/user/target.git"


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].rsplit(":", 1)[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(pid))
                    break
        except OSError:
            continue
    return result


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def listener_addresses(port):
    addresses = []
    for table, family in (("/proc/net/tcp", socket.AF_INET), ("/proc/net/tcp6", socket.AF_INET6)):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    address_hex, port_hex = fields[1].split(":")
                    if int(port_hex, 16) != port or fields[3] != "0A":
                        continue
                    if family == socket.AF_INET:
                        raw = bytes.fromhex(address_hex)[::-1]
                    else:
                        raw = b"".join(bytes.fromhex(address_hex[i:i+8])[::-1] for i in range(0, 32, 8))
                    addresses.append(socket.inet_ntop(family, raw))
        except FileNotFoundError:
            pass
    return addresses


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def exercise_daemon(command, cwd=None, extra_env=None):
    port = free_port()
    token = "audit_" + uuid.uuid4().hex
    env = os.environ.copy()
    env.update({
        "BIND_HOST": "127.0.0.1",
        "BIND_PORT": str(port),
        "AUTH_TOKEN": token,
    })
    if extra_env:
        env.update(extra_env)

    proc = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        deadline = time.time() + 8
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"Daemon command exited early with status {proc.returncode}: {command}")
            try:
                requests.post(f"http://127.0.0.1:{port}/notify", timeout=0.25)
                break
            except requests.RequestException:
                time.sleep(0.1)
        else:
            pytest.fail(f"Daemon command did not listen on BIND_PORT={port}: {command}")

        assert listener_addresses(port) == ["127.0.0.1"], (
            f"Daemon did not bind specifically to BIND_HOST=127.0.0.1; "
            f"listener addresses were {listener_addresses(port)}"
        )

        valid = requests.post(
            f"http://127.0.0.1:{port}/notify",
            headers={"Authorization": f"Bearer {token}"},
            json={"event": "push"},
            timeout=3,
        )
        assert valid.status_code == 200, f"Random AUTH_TOKEN was not accepted: {valid.status_code} {valid.text}"

        invalid = requests.post(
            f"http://127.0.0.1:{port}/notify",
            headers={"Authorization": "Bearer wrong_" + uuid.uuid4().hex},
            json={"event": "push"},
            timeout=3,
        )
        assert invalid.status_code in (401, 403), f"Random invalid token was accepted: {invalid.status_code}"

        wrong_event = requests.post(
            f"http://127.0.0.1:{port}/notify",
            headers={"Authorization": f"Bearer {token}"},
            json={"event": "audit_" + uuid.uuid4().hex},
            timeout=3,
        )
        assert wrong_event.status_code == 400, f"Non-push event should return 400, got {wrong_event.status_code}"
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=3)


def test_venv_exists_and_package_installed():
    assert os.path.isdir(VENV_DIR), f"Virtual environment directory {VENV_DIR} does not exist."
    python = os.path.join(VENV_DIR, "bin", "python")
    executable = os.path.join(VENV_DIR, "bin", "git-notifier")
    assert os.path.isfile(python), "Python executable not found in the virtual environment."
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Installed git-notifier console script is missing or not executable."

    result = subprocess.run(
        [python, "-c", "import notifier.server; from importlib.metadata import version; print(version('git-notifier')); print(notifier.server.__file__)"],
        check=True,
        capture_output=True,
        text=True,
    )
    lines = result.stdout.strip().splitlines()
    assert lines and lines[0] == "2.0.0", f"git-notifier 2.0.0 is not installed in the virtual environment: {result.stdout}"
    assert len(lines) >= 2 and os.path.isfile(lines[1]), "The installed notifier.server module cannot be located."


def test_modified_vendor_source_executes_with_environment():
    source = os.path.join(VENDOR_DIR, "notifier", "server.py")
    assert os.path.isfile(source), f"Vendored source {source} is missing."
    exercise_daemon(
        ["/usr/bin/python3", "-m", "notifier.server"],
        cwd=VENDOR_DIR,
        extra_env={"PYTHONPATH": VENDOR_DIR},
    )


def test_installed_console_script_executes_with_environment():
    exercise_daemon([os.path.join(VENV_DIR, "bin", "git-notifier")])


def test_wrapper_and_running_services():
    assert os.path.isfile(WRAPPER), f"Wrapper script {WRAPPER} does not exist."
    assert os.access(WRAPPER, os.X_OK), f"Wrapper script {WRAPPER} is not executable."
    subprocess.run(["bash", "-n", WRAPPER], check=True)
    text = open(WRAPPER).read()
    assert re.search(r"(?:source|\.)\s+[^\n]*venv/bin/activate", text), "Wrapper does not activate /home/user/venv."
    assert re.search(r"export\s+BIND_HOST\s*=\s*['\"]?127\.0\.0\.1['\"]?", text), "Wrapper does not export BIND_HOST=127.0.0.1."
    assert re.search(r"export\s+BIND_PORT\s*=\s*['\"]?8080['\"]?", text), "Wrapper does not export BIND_PORT=8080."
    assert re.search(r"export\s+AUTH_TOKEN\s*=\s*['\"]?secure_admin_99['\"]?", text), "Wrapper does not export AUTH_TOKEN=secure_admin_99."
    assert "git-notifier" in text, "Wrapper does not start git-notifier."

    daemon_pids = listening_pids(8080)
    assert daemon_pids, "Nothing is listening on port 8080."
    daemon_cmds = [cmdline(pid) for pid in daemon_pids]
    assert any("/home/user/venv/bin/git-notifier" in value for value in daemon_cmds), (
        f"Port 8080 is not owned by the installed git-notifier: {daemon_cmds}"
    )

    socat_pids = listening_pids(9090)
    assert socat_pids, "Nothing is listening on port 9090."
    socat_cmds = [cmdline(pid) for pid in socat_pids]
    assert any(
        "socat" in value and "LISTEN:9090" in value.upper()
        and "127.0.0.1:8080" in value
        for value in socat_cmds
    ), f"Port 9090 is not owned by a socat forwarder to 127.0.0.1:8080: {socat_cmds}"


def test_git_repo_and_hook():
    assert os.path.isdir(REPO_DIR), f"Bare git repository {REPO_DIR} does not exist."
    assert os.path.isfile(os.path.join(REPO_DIR, "config")), f"{REPO_DIR} does not appear to be a valid git repository."
    bare = subprocess.run(["git", "-C", REPO_DIR, "rev-parse", "--is-bare-repository"], check=True, capture_output=True, text=True)
    assert bare.stdout.strip() == "true", f"{REPO_DIR} is not a bare Git repository."

    hook_path = os.path.join(REPO_DIR, "hooks", "post-receive")
    assert os.path.isfile(hook_path), f"Git hook {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"Git hook {hook_path} is not executable."
    hook_text = open(hook_path, errors="replace").read()
    assert "http://127.0.0.1:8080/notify" in hook_text, "Hook does not target the required daemon URL."


def test_http_protocol_success():
    response = requests.post(
        "http://127.0.0.1:9090/notify",
        headers={"Authorization": "Bearer secure_admin_99"},
        json={"event": "push"},
        timeout=5,
    )
    assert response.status_code == 200, f"Expected HTTP 200 through socat, got {response.status_code}: {response.text}"


def test_http_protocol_auth_failure_and_body_validation():
    invalid_token = "wrong_" + uuid.uuid4().hex
    response = requests.post(
        "http://127.0.0.1:9090/notify",
        headers={"Authorization": f"Bearer {invalid_token}"},
        json={"event": "push"},
        timeout=5,
    )
    assert response.status_code in (401, 403), f"Expected 401/403 for invalid token, got {response.status_code}."

    response = requests.post(
        "http://127.0.0.1:9090/notify",
        headers={"Authorization": "Bearer secure_admin_99"},
        json={"event": "not_push_" + uuid.uuid4().hex},
        timeout=5,
    )
    assert response.status_code == 400, f"Expected 400 for a non-push event, got {response.status_code}."


def test_git_push_trigger_observes_webhook():
    received = queue.Queue()

    class CaptureHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            received.put((self.path, dict(self.headers), self.rfile.read(length)))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK\n")

        def log_message(self, *args):
            pass

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    old_daemons = listening_pids(8080)
    assert old_daemons, "The configured daemon was not running before the push test."
    for pid in old_daemons:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while listening_pids(8080) and time.time() < deadline:
        time.sleep(0.1)
    assert not listening_pids(8080), "Could not stop the daemon temporarily to observe the hook request."

    server = ReusableHTTPServer(("127.0.0.1", 8080), CaptureHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    clone_dir = tempfile.mkdtemp()
    push_result = None
    try:
        subprocess.run(["git", "clone", REPO_DIR, clone_dir], check=True, capture_output=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=clone_dir, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=clone_dir, check=True)
        unique = uuid.uuid4().hex
        filename = f"test_trigger_{unique}.txt"
        with open(os.path.join(clone_dir, filename), "w") as f:
            f.write("Triggering the webhook via git push.\n")
        subprocess.run(["git", "add", filename], cwd=clone_dir, check=True)
        subprocess.run(["git", "commit", "-m", f"webhook audit {unique}"], cwd=clone_dir, check=True)
        push_result = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/audit-{unique}"],
            cwd=clone_dir,
            capture_output=True,
            text=True,
            timeout=15,
        )
        request_path, headers, body = received.get(timeout=8)
    finally:
        shutil.rmtree(clone_dir)
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)
        restart = subprocess.run(["bash", WRAPPER], capture_output=True, text=True, timeout=8)
        assert restart.returncode == 0, f"Wrapper could not restart the daemon: {restart.stderr}"

    assert push_result is not None and push_result.returncode == 0, f"Git push failed: {getattr(push_result, 'stderr', '')}"
    assert request_path == "/notify", f"Hook posted to the wrong path: {request_path}"
    assert headers.get("Authorization") == "Bearer secure_admin_99", "Hook sent the wrong or missing Authorization header."
    try:
        payload = json.loads(body)
    except Exception as exc:
        pytest.fail(f"Hook did not send valid JSON: {body!r}: {exc}")
    assert payload == {"event": "push"}, f"Hook sent the wrong JSON body: {payload!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
