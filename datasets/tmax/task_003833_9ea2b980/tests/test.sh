#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import pwd
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest

USER = "user"
USER_UID = pwd.getpwnam(USER).pw_uid
WORKSPACE = "/home/user/workspace"
BARE_REPO = "/home/user/staging.git"
DEPLOY_TARGET = "/home/user/deploy_target"
NGINX_CONF = "/home/user/config/nginx.conf"
HOOK = "/home/user/staging.git/hooks/post-receive"
SOCKET = "/home/user/run/app.sock"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, **kwargs)


def git_output(repo, *args):
    result = run(["runuser", "-u", USER, "--", "git", "-C", repo, *args])
    assert result.returncode == 0, result.stdout
    return result.stdout.strip()


def process_uid(pid):
    return os.stat(f"/proc/{pid}").st_uid


def process_cmdline(pid):
    return pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")


def process_exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def fuser_pids(path):
    result = subprocess.run(["fuser", path], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL)
    return [int(value) for value in result.stdout.split() if value.isdigit()]


@pytest.fixture(scope="session", autouse=True)
def force_real_deployment():
    # The agent must have made and pushed a new workspace commit before verification.
    workspace_head = git_output(WORKSPACE, "rev-parse", "HEAD")
    workspace_branch = git_output(WORKSPACE, "rev-parse", "--abbrev-ref", "HEAD")
    bare_head = git_output(BARE_REPO, "rev-parse", "refs/heads/master")
    commit_count = int(git_output(WORKSPACE, "rev-list", "--count", "HEAD"))
    assert workspace_branch == "master", "Workspace is not on master"
    assert commit_count >= 2, "No new workspace commit was created"
    assert workspace_head == bare_head, "Workspace HEAD was not pushed to staging master"

    # Remove any pre-existing or spoofed service before exercising the hook.
    subprocess.run(["fuser", "-k", "8080/tcp"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["fuser", "-k", SOCKET], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass
    shutil.rmtree(DEPLOY_TARGET, ignore_errors=True)
    os.makedirs(DEPLOY_TARGET, exist_ok=True)
    os.chown(DEPLOY_TARGET, USER_UID, pwd.getpwnam(USER).pw_gid)

    token = os.urandom(24).hex()
    parent = tempfile.mkdtemp(prefix="verifier-push-", dir="/home/user")
    os.chown(parent, USER_UID, pwd.getpwnam(USER).pw_gid)
    clone = os.path.join(parent, "repo")

    clone_result = run(["runuser", "-u", USER, "--", "git", "clone", BARE_REPO, clone])
    assert clone_result.returncode == 0, clone_result.stdout

    app_path = os.path.join(clone, "app.py")
    assert os.path.isfile(app_path), "Pushed application is missing app.py"
    with open(app_path, "a") as app_file:
        app_file.write(
            f"\n@app.route('/__verifier/{token}')\n"
            f"def verifier_probe_{token}():\n"
            f"    return '{token}'\n"
        )

    add_result = run(["runuser", "-u", USER, "--", "git", "-C", clone, "add", "app.py"])
    assert add_result.returncode == 0, add_result.stdout
    commit_result = run([
        "runuser", "-u", USER, "--", "git", "-C", clone,
        "-c", "user.name=Verifier", "-c", "user.email=verifier@example.invalid",
        "commit", "-m", "Verifier deployment probe"
    ])
    assert commit_result.returncode == 0, commit_result.stdout

    push_result = run(["runuser", "-u", USER, "--", "git", "-C", clone,
                       "push", "origin", "master"], timeout=30)
    assert push_result.returncode == 0, f"git push failed:\n{push_result.stdout}"
    assert "Deployment successful!" in push_result.stdout, (
        "The post-receive hook did not report a successful deployment:\n" + push_result.stdout
    )

    # A random route added only to the pushed commit proves that the newly checked-out
    # WSGI application is being served through port 8080.
    url = f"http://127.0.0.1:8080/__verifier/{token}"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            body = response.read().decode()
            assert response.getcode() == 200
            assert body == token, f"Deployment probe returned unexpected body: {body!r}"
    except urllib.error.URLError as exc:
        pytest.fail(f"Fresh deployment probe failed: {exc}")

    yield
    shutil.rmtree(parent, ignore_errors=True)


def test_nginx_config_fixed():
    assert os.path.isfile(NGINX_CONF), f"Nginx config {NGINX_CONF} does not exist"
    with open(NGINX_CONF) as config_file:
        content = config_file.read()

    assert "server unix:/home/user/run/wrong_app.sock;" not in content, "Nginx config still contains the wrong socket path"
    assert "server unix:/home/user/run/app.sock;" in content, "Nginx config does not contain the correct socket path"

    syntax = run(["runuser", "-u", USER, "--", "nginx", "-t", "-c", NGINX_CONF])
    assert syntax.returncode == 0, syntax.stdout


def test_hook_fixed():
    assert os.path.isfile(HOOK), f"Hook file {HOOK} does not exist"
    assert os.access(HOOK, os.X_OK), "Post-receive hook is not executable"
    with open(HOOK) as hook_file:
        content = hook_file.read()

    assert "TZ=UTC" in content, "Hook is missing TZ=UTC environment variable"
    assert "LANG=en_US.UTF-8" in content, "Hook is missing LANG=en_US.UTF-8 environment variable"
    assert "gunicorn" in content, "Hook is missing gunicorn command"


def test_service_health():
    url = "http://127.0.0.1:8080/health"
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=5) as response:
            assert response.getcode() == 200, f"Expected HTTP 200, got {response.getcode()}"
            data = json.loads(response.read().decode())
            assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"
            assert data == {"status": "ok"}, f"Health response contains unexpected data: {data}"
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to {url}: {exc}")
    except json.JSONDecodeError:
        pytest.fail("Failed to decode JSON response from health endpoint")


def test_processes_running():
    try:
        subprocess.check_output(["pgrep", "-f", "nginx"])
    except subprocess.CalledProcessError:
        pytest.fail("Nginx is not running")
    try:
        subprocess.check_output(["pgrep", "-f", "gunicorn"])
    except subprocess.CalledProcessError:
        pytest.fail("Gunicorn is not running")

    listener_pids = fuser_pids("8080/tcp")
    assert listener_pids, "Nothing is listening on port 8080"
    nginx_pids = [pid for pid in listener_pids if os.path.basename(process_exe(pid)) == "nginx"]
    assert nginx_pids, "Port 8080 is not owned by a real Nginx process"
    assert all(process_uid(pid) == USER_UID for pid in nginx_pids), "Nginx is not running as user"

    socket_pids = fuser_pids(SOCKET)
    assert socket_pids, "No process owns the configured Gunicorn socket"
    gunicorn_pids = [pid for pid in socket_pids if "gunicorn" in process_cmdline(pid)]
    assert gunicorn_pids, "The application socket is not owned by Gunicorn"

    valid_environment = False
    for pid in gunicorn_pids:
        assert process_uid(pid) == USER_UID, "Gunicorn is not running as user"
        cwd = os.path.realpath(f"/proc/{pid}/cwd")
        assert cwd == DEPLOY_TARGET, f"Gunicorn is running from unexpected directory {cwd}"
        environment = pathlib.Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        if b"TZ=UTC" in environment and b"LANG=en_US.UTF-8" in environment:
            valid_environment = True
    assert valid_environment, "Gunicorn did not receive TZ=UTC and LANG=en_US.UTF-8"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
