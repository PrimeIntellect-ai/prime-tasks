#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import signal
import subprocess
import time
import pytest

BACKEND = "/home/user/backend.git"
WORKSPACE = "/home/user/workspace"
DEPLOYED = "/home/user/deployed_app"
HOOK = f"{BACKEND}/hooks/post-receive"
AUTO = "/home/user/auto_deploy.py"
NGINX_CONF = "/home/user/nginx/nginx.conf"


def git(repo, *args):
    return subprocess.check_output(
        ["git", "-c", f"safe.directory={repo}", *args],
        cwd=repo,
        stderr=subprocess.STDOUT,
    )


def expected_port():
    with open(NGINX_CONF, "r") as f:
        config = f.read()
    match = re.search(r"proxy_pass\s+http://127\.0\.0\.1:(\d+)\s*;", config)
    assert match, "Could not derive the backend port from nginx.conf"
    return int(match.group(1))


def curl(url):
    return subprocess.check_output(
        ["curl", "-sS", "--max-time", "5", url],
        stderr=subprocess.STDOUT,
    )


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                    if local_port == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def stop_backend_processes(port):
    victims = set(listener_pids(port))
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ")
            if b"app.py" in cmdline:
                victims.add(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.1)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_backend(port, expected=b"Hello from Backend!"):
    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        try:
            body = curl(f"http://127.0.0.1:{port}")
            if body == expected:
                return
            last_error = AssertionError(f"Unexpected backend response: {body!r}")
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            last_error = exc
        time.sleep(0.2)
    pytest.fail(f"Backend did not become ready on port {port}: {last_error}")


def assert_deployed_process(port):
    pids = listener_pids(port)
    assert pids, f"No process is listening on the configured backend port {port}"
    for pid in pids:
        try:
            cwd = os.path.realpath(f"/proc/{pid}/cwd")
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ")
            if cwd == DEPLOYED and b"app.py" in cmdline and b"python3" in cmdline:
                return
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    pytest.fail("The listener was not python3 app.py started from /home/user/deployed_app")


def clear_deployed():
    os.makedirs(DEPLOYED, exist_ok=True)
    for name in os.listdir(DEPLOYED):
        path = os.path.join(DEPLOYED, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def test_final_result_file():
    result_path = "/home/user/final_result.txt"
    assert os.path.exists(result_path), f"File {result_path} does not exist."
    with open(result_path, "r") as f:
        content = f.read().strip()
    assert content == "Hello from Backend!", f"Expected 'Hello from Backend!' in {result_path}, got '{content}'"
    with open(result_path, "rb") as f:
        saved = f.read()
    assert saved == curl("http://127.0.0.1:8080"), "final_result.txt is not the exact current stdout from the Nginx proxy curl"


def test_post_receive_hook_exists_and_executable():
    assert os.path.exists(HOOK), f"Hook {HOOK} does not exist."
    assert os.path.isfile(HOOK), f"Hook {HOOK} is not a regular file."
    assert os.access(HOOK, os.X_OK), f"Hook {HOOK} is not executable."


def test_git_commit_message():
    try:
        output = git(BACKEND, "log", "-1", "--pretty=%B").decode("utf-8").strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to get git log from {BACKEND}: {e.output.decode('utf-8')}")
    assert "Fix backend port" in output, f"Expected commit message to contain 'Fix backend port', got '{output}'"


def test_auto_deploy_script_exists():
    assert os.path.exists(AUTO), f"Script {AUTO} does not exist."
    assert os.path.isfile(AUTO), f"{AUTO} is not a file."


def test_app_running_on_correct_port():
    try:
        output = subprocess.check_output(
            ["curl", "-s", "http://127.0.0.1:9000"],
            stderr=subprocess.STDOUT
        ).decode("utf-8").strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to curl backend directly on port 9000: {e}")
    assert output == "Hello from Backend!", f"Direct curl to backend port 9000 failed or returned incorrect output: '{output}'"


def test_hook_and_auto_deploy_behavior():
    port = expected_port()
    assert port == 9000, f"Expected Nginx to proxy to port 9000, got {port}"

    # Exercise the hook itself from a clean deployment directory and with no
    # pre-existing listener that could counterfeit a successful deployment.
    stop_backend_processes(port)
    clear_deployed()
    head = git(BACKEND, "rev-parse", "HEAD").decode().strip()
    update = f"{'0' * 40} {head} refs/heads/master\n"
    completed = subprocess.run(
        ["runuser", "-u", "user", "--", "env", f"GIT_DIR={BACKEND}", HOOK],
        cwd=BACKEND,
        input=update.encode(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
    )
    assert completed.returncode == 0, f"post-receive exited with status {completed.returncode}"
    deployed_app = os.path.join(DEPLOYED, "app.py")
    assert os.path.isfile(deployed_app), "post-receive did not check out app.py into deployed_app"
    expected_app = git(BACKEND, "show", f"{head}:app.py")
    with open(deployed_app, "rb") as f:
        assert f.read() == expected_app, "post-receive did not deploy app.py from the latest bare-repository commit"
    wait_for_backend(port)
    assert_deployed_process(port)

    # Give auto_deploy.py a fresh, unpredictable app.py modification. A real
    # implementation must stage it, create a new commit, push it, and thereby
    # cause the tested hook to refresh the deployment.
    nonce = secrets.token_hex(16)
    workspace_app = os.path.join(WORKSPACE, "app.py")
    with open(workspace_app, "ab") as f:
        f.write(f"\n# verifier deployment nonce: {nonce}\n".encode())
    old_head = git(BACKEND, "rev-parse", "HEAD").decode().strip()

    completed = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", AUTO],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
    )
    assert completed.returncode == 0, f"auto_deploy.py exited with status {completed.returncode}"

    new_head = git(BACKEND, "rev-parse", "HEAD").decode().strip()
    assert new_head != old_head, "auto_deploy.py did not push a new commit to origin"
    message = git(BACKEND, "log", "-1", "--pretty=%B").decode().strip()
    assert message == "Fix backend port", f"auto_deploy.py used the wrong commit message: {message!r}"
    committed_app = git(BACKEND, "show", f"{new_head}:app.py")
    assert nonce.encode() in committed_app, "auto_deploy.py did not stage and commit the modified workspace/app.py"
    with open(deployed_app, "rb") as f:
        assert f.read() == committed_app, "the pushed commit did not trigger deployment of the new app.py"
    wait_for_backend(port)
    assert_deployed_process(port)
    assert curl("http://127.0.0.1:8080") == b"Hello from Backend!", "Nginx does not successfully proxy to the deployed backend"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
