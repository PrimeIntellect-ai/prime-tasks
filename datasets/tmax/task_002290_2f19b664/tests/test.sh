#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def test_start_sh_modified():
    path = "/home/user/start.sh"
    assert os.path.isfile(path), f"Expected file {path} to exist."

    with open(path, "r") as f:
        content = f.read()

    state_idx = content.find("state_svc.py")
    deploy_idx = content.find("deploy_svc.py")
    sleep_idx = content.find("sleep")

    assert state_idx != -1, "start.sh is missing state_svc.py"
    assert deploy_idx != -1, "start.sh is missing deploy_svc.py"
    assert sleep_idx != -1, "start.sh is missing a sleep command"

    assert state_idx < deploy_idx, "state_svc.py must be started before deploy_svc.py in start.sh"
    assert state_idx < sleep_idx < deploy_idx, "The sleep command must be placed between starting state_svc.py and deploy_svc.py"


def test_start_sh_uses_sleep_two():
    with open("/home/user/start.sh", "r") as f:
        content = "\n".join(line.split("#", 1)[0] for line in f)
    pattern = r"(?:^|[;\n]|&&|\|\|)\s*sleep\s+2\s*(?=;|\n|&&|\|\||$)"
    assert re.search(pattern, content), "start.sh must contain an actual 'sleep 2' command"


def test_post_receive_executable():
    path = "/home/user/registry.git/hooks/post-receive"
    assert os.path.isfile(path), f"Expected file {path} to exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f"Expected {path} to have executable permissions."


def test_workspace_and_trigger():
    path = "/home/user/workspace/trigger.txt"
    assert os.path.isfile(path), f"Expected file {path} to exist. Did you clone the repo and create trigger.txt?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "deploy", f"Expected trigger.txt to contain 'deploy', but got '{content}'"


def test_deploy_log_exists_and_content():
    path = "/home/user/deploy.log"
    assert os.path.isfile(path), f"Expected file {path} to exist. The deployment hook likely did not trigger successfully."

    with open(path, "r") as f:
        content = f.read()

    assert content == "Deployment successful!\n", f"Expected deploy.log to contain exactly 'Deployment successful!\\n', but got {repr(content)}"


def git(*args, cwd=None, timeout=15):
    return subprocess.run(
        ["git", *args], cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout, check=True
    ).stdout.strip()


def test_trigger_was_committed_and_pushed_to_master():
    workspace = "/home/user/workspace"
    registry = "/home/user/registry.git"
    assert os.path.isdir(os.path.join(workspace, ".git")), "workspace must be a Git clone"

    workspace_head = git("rev-parse", "HEAD", cwd=workspace)
    bare_master = git("--git-dir", registry, "rev-parse", "refs/heads/master")
    assert workspace_head == bare_master, "workspace HEAD was not pushed to origin master"
    assert git("branch", "--show-current", cwd=workspace) == "master", "workspace must be on master"
    assert git("show", "HEAD:trigger.txt", cwd=workspace).strip() == "deploy", \
        "the pushed commit must contain trigger.txt with the word deploy"

    origin = git("remote", "get-url", "origin", cwd=workspace)
    if origin.startswith("file://"):
        origin = origin[7:]
    assert os.path.realpath(origin) == os.path.realpath(registry), \
        "workspace origin must be /home/user/registry.git"


def service_pids(script_path):
    found = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if script_path in argv:
            found.add(int(entry))
    return found


def get(url):
    with urllib.request.urlopen(url, timeout=3) as response:
        return response.status, response.read()


def test_services_are_running_and_are_the_expected_services():
    assert service_pids("/home/user/state_svc.py"), "state_svc.py is not running"
    assert service_pids("/home/user/deploy_svc.py"), "deploy_svc.py is not running"

    status, body = get("http://127.0.0.1:8081/")
    assert status == 200 and body == b"State OK", "State Service is not responding correctly on port 8081"

    try:
        get("http://127.0.0.1:8080/verifier-health")
        assert False, "Deploy Service should return 404 for an unknown route"
    except urllib.error.HTTPError as exc:
        assert exc.code == 404, f"Unexpected Deploy Service response: {exc.code}"


def test_real_push_executes_hook_and_creates_log_via_deploy_service():
    state_before = service_pids("/home/user/state_svc.py")
    deploy_before = service_pids("/home/user/deploy_svc.py")
    assert state_before and deploy_before, "both services must already be running"

    log_path = "/home/user/deploy.log"

    # First exercise the running Deploy Service itself and verify its documented effect.
    if os.path.exists(log_path):
        os.unlink(log_path)
    status, body = get("http://127.0.0.1:8080/deploy")
    assert status == 200 and body == b"Deployed", "Deploy Service /deploy endpoint is not working"
    with open(log_path, "r") as f:
        assert f.read() == "Deployment successful!\n"

    # Remove that result, then require a real Git push to recreate it through post-receive.
    os.unlink(log_path)
    tempdir = tempfile.mkdtemp(prefix="verifier-push-")
    try:
        repo = os.path.join(tempdir, "repo")
        git("clone", "/home/user/registry.git", repo, timeout=20)
        git("config", "user.name", "Verifier", cwd=repo)
        git("config", "user.email", "verifier@localhost", cwd=repo)
        nonce = f"verification-{time.time_ns()}"
        with open(os.path.join(repo, "verifier-trigger.txt"), "w") as f:
            f.write(nonce + "\n")
        git("add", "verifier-trigger.txt", cwd=repo)
        git("commit", "-m", "Verify post-receive deployment", cwd=repo)
        git("push", "origin", "HEAD:master", cwd=repo, timeout=20)
    finally:
        shutil.rmtree(tempdir, ignore_errors=True)

    deadline = time.time() + 5
    while time.time() < deadline and not os.path.isfile(log_path):
        time.sleep(0.1)
    assert os.path.isfile(log_path), "a real push did not cause the hook to create deploy.log"
    with open(log_path, "r") as f:
        assert f.read() == "Deployment successful!\n", "hook-triggered deploy.log has incorrect content"

    assert state_before & service_pids("/home/user/state_svc.py"), "State Service did not stay running"
    assert deploy_before & service_pids("/home/user/deploy_svc.py"), "Deploy Service did not stay running"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
