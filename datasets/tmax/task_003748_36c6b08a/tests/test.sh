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
import re
import signal
import subprocess
import tempfile
import time

import pytest
import requests


def ssh_environment():
    env = os.environ.copy()
    env["GIT_SSH_COMMAND"] = "ssh -i /home/user/.ssh/id_rsa -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no"
    return env


def test_routing_to_metrics_server():
    # Verify that 10.0.0.5 is reachable (the student should have added the route/IP)
    try:
        response = requests.get("http://10.0.0.5:8080/", timeout=2)
        # Even if it's a 404, the server is reachable
    except requests.RequestException as e:
        pytest.fail(f"Metrics server at 10.0.0.5:8080 is not reachable. Routing or interface issue: {e}")


def test_sshd_configuration():
    # Verify the SSH daemon configuration for public key auth
    with open("/home/user/sshd_config", "r") as f:
        config = f.read()

    assert "PubkeyAuthentication yes" in config, "PubkeyAuthentication is not enabled in sshd_config"
    assert "AuthorizedKeysFile" in config, "AuthorizedKeysFile is not specified in sshd_config"


def test_git_hook_exists_and_executable():
    hook_path = "/home/user/git-server/repo.git/hooks/post-receive"
    assert os.path.isfile(hook_path), "post-receive hook does not exist"
    assert os.access(hook_path, os.X_OK), "post-receive hook is not executable"

    with open(hook_path, "r") as f:
        hook_content = f.read()

    assert "curl" in hook_content, "post-receive hook does not contain a curl command"
    assert "$METRICS_URL" in hook_content or "${METRICS_URL}" in hook_content, "post-receive hook does not use the METRICS_URL environment variable"


def test_metrics_url_is_defined_in_noninteractive_ssh_session():
    result = subprocess.run(
        [
            "ssh", "-i", "/home/user/.ssh/id_rsa", "-p", "2222",
            "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
            "user@127.0.0.1", "printf '%s' \"$METRICS_URL\"",
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.stdout == "http://10.0.0.5:8080", (
        "METRICS_URL is not correctly defined during a non-interactive SSH session; "
        f"got {result.stdout!r}"
    )


def stop_existing_metrics_listener():
    result = subprocess.run(["ss", "-ltnp"], capture_output=True, text=True, check=True)
    for line in result.stdout.splitlines():
        if re.search(r"(?:10\.0\.0\.5|0\.0\.0\.0|\*)\:8080\b", line):
            for pid_text in re.findall(r"pid=(\d+)", line):
                pid = int(pid_text)
                if pid != os.getpid():
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
    time.sleep(0.5)


def test_git_push_triggers_hook():
    # Replace the permissive metrics endpoint with a verifier-controlled receiver
    # so the hook's actual method, URL, and body can be observed.
    stop_existing_metrics_listener()

    with tempfile.TemporaryDirectory() as capture_dir:
        capture_path = os.path.join(capture_dir, "request.json")
        ready_path = os.path.join(capture_dir, "ready")
        receiver_code = r'''
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

capture_path, ready_path = sys.argv[1], sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", "replace")
        with open(capture_path, "w") as f:
            json.dump({"method": "POST", "path": self.path, "body": body}, f)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, format, *args):
        pass

server = HTTPServer(("10.0.0.5", 8080), Handler)
with open(ready_path, "w") as f:
    f.write("ready")
server.handle_request()
'''
        receiver = subprocess.Popen(
            ["python3", "-c", receiver_code, capture_path, ready_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        try:
            deadline = time.time() + 5
            while not os.path.exists(ready_path) and time.time() < deadline:
                if receiver.poll() is not None:
                    stdout, stderr = receiver.communicate()
                    pytest.fail(f"Verifier metrics receiver failed to start: {stdout}{stderr}")
                time.sleep(0.05)
            assert os.path.exists(ready_path), "Verifier metrics receiver did not become ready"

            with tempfile.TemporaryDirectory() as tmpdir:
                env = ssh_environment()

                # Clone
                clone_cmd = ["git", "clone", "user@127.0.0.1:/home/user/git-server/repo.git", tmpdir]
                try:
                    subprocess.run(clone_cmd, env=env, check=True, capture_output=True, text=True)
                except subprocess.CalledProcessError as e:
                    pytest.fail(f"Failed to clone repository via SSH: {e.stderr}")

                # Commit
                subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmpdir, check=True)
                subprocess.run(["git", "config", "user.name", "Test User"], cwd=tmpdir, check=True)
                subprocess.run(["git", "commit", "--allow-empty", "-m", "Test commit"], cwd=tmpdir, check=True)

                # Push
                try:
                    push_result = subprocess.run(
                        ["git", "push", "origin", "master"], cwd=tmpdir, env=env,
                        check=True, capture_output=True, text=True, timeout=20
                    )
                    output = push_result.stderr + push_result.stdout
                    # Keep the original curl failure checks.
                    assert "Failed to connect" not in output, f"Curl failed to connect during git push: {output}"
                    assert "Could not resolve host" not in output, f"Curl could not resolve host during git push: {output}"
                except subprocess.CalledProcessError as e:
                    pytest.fail(f"Failed to push to repository: {e.stderr}")

            deadline = time.time() + 5
            while not os.path.exists(capture_path) and time.time() < deadline:
                time.sleep(0.05)
            assert os.path.isfile(capture_path), "Git push did not send any request to the Metrics Server"

            with open(capture_path) as f:
                request = json.load(f)
            assert request["method"] == "POST", "Metrics request was not an HTTP POST"
            assert request["path"] == "/push", f"Metrics request used the wrong path: {request['path']!r}"
            assert request["body"] == "event=pushed", f"Metrics request used the wrong payload: {request['body']!r}"
        finally:
            if receiver.poll() is None:
                receiver.terminate()
                try:
                    receiver.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    receiver.kill()
                    receiver.wait()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
