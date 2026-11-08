#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import signal
import socket
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid


def run(cmd, cwd=None, timeout=20):
    return subprocess.run(
        cmd, cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout, check=True
    )


def listener_pids(port):
    result = subprocess.run(
        ["lsof", "-t", f"-iTCP:{port}", "-sTCP:LISTEN"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    return {int(x) for x in result.stdout.split() if x.isdigit()}


def wait_for_body(port, expected, timeout=12):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=1)
            conn.request("GET", "/")
            response = conn.getresponse()
            body = response.read().decode("utf-8")
            conn.close()
            if response.status == 200 and body == expected:
                return
            last_error = AssertionError(
                f"port {port} returned status {response.status}, body {body!r}"
            )
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    raise AssertionError(f"service did not return {expected!r} on port {port}: {last_error}")


def wait_for_no_pid(pids, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if all(not os.path.exists(f"/proc/{pid}") for pid in pids):
            return
        time.sleep(0.1)
    alive = [pid for pid in pids if os.path.exists(f"/proc/{pid}")]
    raise AssertionError(f"old listener processes were not terminated: {alive}")


def make_app(token):
    return f'''#!/usr/bin/env python3
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

TOKEN = {token!r}

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            data = TOKEN.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        pass

HTTPServer(("", int(os.environ["APP_PORT"])), Handler).serve_forever()
'''


def commit_and_push(repo, source, message):
    app_path = os.path.join(repo, "app.py")
    with open(app_path, "w") as f:
        f.write(source)
    run(["git", "add", "app.py"], cwd=repo)
    run(["git", "commit", "-m", message], cwd=repo)
    run(["git", "push", "origin", "HEAD:refs/heads/main"], cwd=repo, timeout=20)
    return run(["git", "rev-parse", "HEAD"], cwd=repo).stdout.strip()


def test_result_log_content():
    log_path = "/home/user/result.log"
    assert os.path.exists(log_path), f"File not found: {log_path}"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "MICROSERVICE_V1_ACTIVE", f"Incorrect content in {log_path}: {content}"


def test_service_running_and_responding():
    url = "http://localhost:8282/"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as response:
            body = response.read().decode("utf-8").strip()
            assert body == "MICROSERVICE_V1_ACTIVE", f"Incorrect response from service: {body}"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to service at {url}: {e}"


def test_git_hook_executable():
    hook_path = "/home/user/app.git/hooks/post-receive"
    assert os.path.exists(hook_path), f"Hook not found: {hook_path}"
    assert os.path.isfile(hook_path), f"Hook is not a regular file: {hook_path}"
    st = os.stat(hook_path)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"Hook is not executable: {hook_path}"
    with open(hook_path, "rb") as f:
        first_line = f.readline().lower()
    assert first_line.startswith(b"#!") and b"python" in first_line, "post-receive is not a Python executable"
    run(["python3", "-m", "py_compile", hook_path])


def test_bare_git_repo():
    repo_path = "/home/user/app.git"
    assert os.path.isdir(repo_path), f"Repo directory not found: {repo_path}"
    config_path = os.path.join(repo_path, "config")
    assert os.path.exists(config_path), f"Git config not found in {repo_path}"
    with open(config_path, "r") as f:
        config_content = f.read()
    assert "bare = true" in config_content.lower(), f"Repository at {repo_path} is not configured as bare."
    assert run(["git", "--git-dir", repo_path, "rev-parse", "--is-bare-repository"]).stdout.strip() == "true"
    run(["git", "--git-dir", repo_path, "rev-parse", "refs/heads/main"])


def test_env_sh_exists():
    env_path = "/home/user/env.sh"
    assert os.path.exists(env_path), f"Environment file not found: {env_path}"
    with open(env_path, "r") as f:
        content = f.read()
    assert "APP_PORT=8282" in content, f"APP_PORT=8282 not found in {env_path}"
    assert content == "export APP_PORT=8282\n" or content == "export APP_PORT=8282"


def test_source_clone_and_initial_deployment_match_main():
    src = "/home/user/app_src"
    assert os.path.isdir(os.path.join(src, ".git")), "app_src is not a Git clone"
    assert os.path.isfile(os.path.join(src, "app.py")), "app_src/app.py is missing"
    assert run(["git", "status", "--porcelain"], cwd=src).stdout == "", "app_src has uncommitted changes"
    assert run(["git", "branch", "--show-current"], cwd=src).stdout.strip() == "main"
    src_head = run(["git", "rev-parse", "HEAD"], cwd=src).stdout.strip()
    bare_head = run(["git", "--git-dir", "/home/user/app.git", "rev-parse", "refs/heads/main"]).stdout.strip()
    assert src_head == bare_head, "app_src main was not committed and pushed to app.git"
    remote = run(["git", "remote", "get-url", "origin"], cwd=src).stdout.strip()
    if remote.startswith("file://"):
        remote = remote[7:]
    if not os.path.isabs(remote):
        remote = os.path.join(src, remote)
    assert os.path.realpath(remote) == os.path.realpath("/home/user/app.git"), "app_src origin is not app.git"
    deployed = "/home/user/app_run/app.py"
    assert os.path.isfile(deployed), "deployed app_run/app.py is missing"
    committed = run(["git", "--git-dir", "/home/user/app.git", "show", "main:app.py"]).stdout
    with open(deployed) as f:
        assert f.read() == committed, "app_run does not contain the app.py from main"


def test_z_real_push_drives_checkout_restart_env_parsing_and_graceful_stop():
    old_pids = listener_pids(8282)
    assert old_pids, "no initial listener was found on APP_PORT"

    with tempfile.TemporaryDirectory(prefix="verify-deploy-") as td:
        repo = os.path.join(td, "clone")
        run(["git", "clone", "/home/user/app.git", repo])
        run(["git", "config", "user.email", "verifier@example.invalid"], cwd=repo)
        run(["git", "config", "user.name", "Deployment Verifier"], cwd=repo)
        run(["git", "checkout", "-B", "main", "origin/main"], cwd=repo)

        token1 = "HOOK_PUSH_" + uuid.uuid4().hex
        source1 = make_app(token1)
        commit1 = commit_and_push(repo, source1, "verifier deployment one")
        wait_for_body(8282, token1)
        wait_for_no_pid(old_pids)
        assert run(["git", "--git-dir", "/home/user/app.git", "rev-parse", "refs/heads/main"]).stdout.strip() == commit1
        with open("/home/user/app_run/app.py") as f:
            assert f.read() == source1, "hook did not check out the newly pushed main app.py"

        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        dynamic_port = sock.getsockname()[1]
        sock.close()
        assert dynamic_port != 8282

        marker = os.path.join(td, "terminated")
        sentinel_script = os.path.join(td, "sentinel.py")
        with open(sentinel_script, "w") as f:
            f.write('''import os, signal, socket, sys, time\n''')
            f.write(f'''marker = {marker!r}\nport = {dynamic_port!r}\n''')
            f.write('''def stop(sig, frame):\n    with open(marker, "w") as out: out.write(str(sig))\n    sys.exit(0)\nsignal.signal(signal.SIGTERM, stop)\ns = socket.socket()\ns.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\ns.bind(("127.0.0.1", port))\ns.listen(1)\nwhile True: time.sleep(1)\n''')
        sentinel = subprocess.Popen(
            ["python3", sentinel_script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        try:
            deadline = time.time() + 5
            while time.time() < deadline and sentinel.pid not in listener_pids(dynamic_port):
                if sentinel.poll() is not None:
                    raise AssertionError("sentinel listener exited unexpectedly")
                time.sleep(0.1)
            assert sentinel.pid in listener_pids(dynamic_port), "could not establish existing listener"

            with open("/home/user/env.sh", "w") as f:
                f.write(f"export APP_PORT={dynamic_port}\n")

            token2 = "ENV_PUSH_" + uuid.uuid4().hex
            source2 = make_app(token2)
            commit2 = commit_and_push(repo, source2, "verifier deployment two")
            wait_for_body(dynamic_port, token2)
            sentinel.wait(timeout=5)
            assert os.path.exists(marker), "existing listener was not gracefully terminated with SIGTERM"
            assert run(["git", "--git-dir", "/home/user/app.git", "rev-parse", "refs/heads/main"]).stdout.strip() == commit2
            with open("/home/user/app_run/app.py") as f:
                assert f.read() == source2, "second push was not checked out into app_run"
        finally:
            if sentinel.poll() is None:
                sentinel.terminate()
                try:
                    sentinel.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    sentinel.kill()
            for pid in listener_pids(dynamic_port):
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            with open("/home/user/env.sh", "w") as f:
                f.write("export APP_PORT=8282\n")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
