#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import time
import urllib.error
import urllib.request
import uuid

HOOK = "/home/user/app.git/hooks/post-receive"
WORKSPACE = "/home/user/workspace"
BARE_REPO = "/home/user/app.git"
DEPLOY = "/home/user/deploy"
LOG = "/home/user/deploy.log"


def git(repo, *args, timeout=20):
    return subprocess.run(
        ["git", "-c", f"safe.directory={repo}", "-C", repo, *args],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    ).stdout.strip()


def read_pid():
    pid_file = os.path.join(DEPLOY, "server.pid")
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer PID. Found: '{pid_str}'"
    return int(pid_str)


def assert_server_process(pid):
    proc_cmdline = f"/proc/{pid}/cmdline"
    assert os.path.isfile(proc_cmdline), f"Process with PID {pid} is not running."
    with open(proc_cmdline, "rb") as f:
        cmdline = f.read().replace(b"\x00", b" ").decode(errors="replace")
    assert "python" in cmdline.lower() and "server.py" in cmdline, \
        f"Process {pid} is running, but does not appear to be the Python server. Cmdline: {cmdline}"


def assert_server_responds(timeout=5):
    url = "http://127.0.0.1:8080"
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(urllib.request.Request(url), timeout=1) as response:
                assert response.status == 200, f"Expected HTTP 200, got {response.status}"
                return
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            last_error = exc
            time.sleep(0.2)
    assert False, f"Failed to connect to the server at {url}: {last_error}"


def test_post_receive_hook():
    assert os.path.isfile(HOOK), f"Hook file {HOOK} does not exist."
    assert os.access(HOOK, os.X_OK), f"Hook file {HOOK} is not executable."
    with open(HOOK, "r") as f:
        first_line = f.readline().strip()
    assert first_line.startswith("#!") and "python" in first_line.lower(), \
        f"Hook file {HOOK} does not have a valid Python shebang. Found: {first_line}"


def test_deploy_server_py():
    deploy_file = os.path.join(DEPLOY, "server.py")
    assert os.path.isfile(deploy_file), f"Deployed server file {deploy_file} does not exist. Did the hook extract the code?"


def test_deploy_log():
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist."
    with open(LOG, "r") as f:
        content = f.read()
    assert "Deployment successful" in content, f"Log file {LOG} does not contain 'Deployment successful'."


def test_server_running():
    assert_server_process(read_pid())


def test_server_responds():
    assert_server_responds()


def test_z_commit_push_and_fresh_hook_deployment():
    # Before modifying anything, require that the agent's workspace commit was
    # already pushed to the bare repository's main branch.
    assert git(WORKSPACE, "symbolic-ref", "--short", "HEAD") == "main", \
        "The workspace is not on the main branch."
    assert git(WORKSPACE, "remote", "get-url", "origin") == BARE_REPO, \
        "The workspace origin does not point to /home/user/app.git."
    workspace_head = git(WORKSPACE, "rev-parse", "main")
    bare_head = git(BARE_REPO, "rev-parse", "refs/heads/main")
    assert workspace_head == bare_head, \
        "The workspace main commit was not pushed to origin/main before verification."
    git(WORKSPACE, "cat-file", "-e", "HEAD:server.py")

    old_pid = read_pid()
    assert_server_process(old_pid)

    # Create an unpredictable new server.py revision and push it normally. The
    # resulting state must be produced by the installed post-receive hook.
    marker = "verifier-deployment-" + uuid.uuid4().hex
    workspace_server = os.path.join(WORKSPACE, "server.py")
    with open(workspace_server, "a") as f:
        f.write(f"\n# {marker}\n")

    git(WORKSPACE, "add", "server.py")
    subprocess.run(
        ["git", "-c", f"safe.directory={WORKSPACE}", "-C", WORKSPACE,
         "-c", "user.name=Verifier", "-c", "user.email=verifier@example.invalid",
         "commit", "--no-verify", "-m", f"Verifier deployment {marker}"],
        check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=20,
    )

    # Remove the artifacts whose fresh creation demonstrates hook execution.
    if os.path.exists(LOG):
        os.unlink(LOG)
    deployed_server = os.path.join(DEPLOY, "server.py")
    if os.path.exists(deployed_server):
        os.unlink(deployed_server)

    git(WORKSPACE, "push", "origin", "main", timeout=30)

    new_workspace_head = git(WORKSPACE, "rev-parse", "main")
    assert git(BARE_REPO, "rev-parse", "refs/heads/main") == new_workspace_head, \
        "The fresh main commit was not received by the bare repository."

    assert os.path.isfile(deployed_server), \
        "The hook did not extract server.py after the fresh push."
    with open(deployed_server, "r") as f:
        deployed_content = f.read()
    assert marker in deployed_content, \
        "The deployed server.py is not the revision from the fresh push."

    assert os.path.isfile(LOG), "The hook did not recreate /home/user/deploy.log."
    with open(LOG, "r") as f:
        log_content = f.read()
    assert "Deployment successful" in log_content, \
        "The hook did not log 'Deployment successful' for the fresh push."

    new_pid = read_pid()
    assert new_pid != old_pid, "The hook did not record a new server process ID."
    assert_server_process(new_pid)

    deadline = time.time() + 5
    while os.path.exists(f"/proc/{old_pid}") and time.time() < deadline:
        try:
            with open(f"/proc/{old_pid}/stat", "r") as f:
                if f.read().split()[2] == "Z":
                    break
        except (FileNotFoundError, IndexError):
            break
        time.sleep(0.1)
    if os.path.exists(f"/proc/{old_pid}/stat"):
        with open(f"/proc/{old_pid}/stat", "r") as f:
            old_state = f.read().split()[2]
        assert old_state == "Z", f"The old server process {old_pid} was not terminated by the hook."

    assert_server_responds(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
