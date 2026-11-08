#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import time
import tempfile
import urllib.request
import uuid
import pytest

DEPLOY_GIT = "/home/user/deploy.git"
LIVE_DIR = "/home/user/live"
HOOK_PATH = "/home/user/deploy.git/hooks/post-receive"
SOCAT_PID_FILE = "/home/user/socat.pid"
SERVER_LOG = "/home/user/server.log"


def server_processes():
    """Return active python3 -m http.server 8080 processes serving LIVE_DIR."""
    result = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            with open(f"/proc/{pid}/stat", "r") as f:
                stat = f.read().split()
            if len(stat) > 2 and stat[2] == "Z":
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if not args or "python3" not in os.path.basename(args[0]):
                continue
            if "-m" not in args:
                continue
            module_index = args.index("-m") + 1
            if module_index >= len(args) or args[module_index] != "http.server":
                continue
            if "8080" not in args[module_index + 1:]:
                continue
            cwd = os.path.realpath(f"/proc/{pid}/cwd")
            if cwd != os.path.realpath(LIVE_DIR):
                continue
            result[pid] = args
        except (FileNotFoundError, ProcessLookupError, PermissionError, OSError):
            continue
    return result


def process_is_active(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            fields = f.read().split()
        return len(fields) > 2 and fields[2] != "Z"
    except (FileNotFoundError, ProcessLookupError, OSError):
        return False


def wait_for_replacement(old_pids, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        current = server_processes()
        old_active = any(process_is_active(pid) for pid in old_pids)
        new_pids = [pid for pid in current if pid not in old_pids]
        if not old_active and len(new_pids) == 1:
            return new_pids[0]
        time.sleep(0.2)
    pytest.fail(
        f"Hook did not terminate the previous server(s) and start exactly one replacement; "
        f"old PIDs={sorted(old_pids)}, current={server_processes()}"
    )


def wait_for_http(url, expected, timeout=12):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                body = response.read().decode("utf-8").strip()
            if body == expected:
                return
            last_error = AssertionError(f"Expected {expected!r}, got {body!r}")
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    pytest.fail(f"Failed to fetch expected deployment from {url}: {last_error}")


def git_run(args, cwd, timeout=20):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, timeout=timeout)


def test_bare_repo_exists():
    """Verify that the deploy.git directory is a bare git repository."""
    assert os.path.isdir(DEPLOY_GIT), f"{DEPLOY_GIT} directory does not exist."
    config_path = os.path.join(DEPLOY_GIT, "config")
    assert os.path.isfile(config_path), f"Git config not found at {config_path}."
    with open(config_path, "r") as f:
        content = f.read()
    assert "bare = true" in content.lower(), f"{DEPLOY_GIT} is not a bare repository."


def test_live_directory_exists():
    """Verify that the live directory exists."""
    assert os.path.isdir(LIVE_DIR), f"{LIVE_DIR} directory does not exist."


def test_hook_exists_and_executable():
    """Verify that the post-receive hook exists and is executable."""
    assert os.path.isfile(HOOK_PATH), f"Hook not found at {HOOK_PATH}."
    assert os.access(HOOK_PATH, os.X_OK), f"Hook at {HOOK_PATH} is not executable."


def test_socat_pid_and_process():
    """Verify socat.pid exists and points to a running socat process."""
    assert os.path.isfile(SOCAT_PID_FILE), f"{SOCAT_PID_FILE} does not exist."
    with open(SOCAT_PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"{SOCAT_PID_FILE} does not contain a valid PID."
    pid = int(pid_str)
    try:
        cmdline_path = f"/proc/{pid}/cmdline"
        assert os.path.isfile(cmdline_path), f"Process with PID {pid} is not running."
        with open(cmdline_path, "rb") as f:
            cmdline = f.read().replace(b"\x00", b" ").decode(errors="replace")
        assert "socat" in cmdline, f"Process {pid} is not a socat process. Cmdline: {cmdline}"
    except Exception as exc:
        pytest.fail(f"Failed to verify socat process: {exc}")


def test_git_push_and_deployment():
    """Push twice and verify deployment, hook-started server replacement, and proxying."""
    first_string = "deploy-first-" + uuid.uuid4().hex
    second_string = "deploy-second-" + uuid.uuid4().hex
    initial_servers = set(server_processes())

    # Remove any stale log so later content must be produced by the tested server.
    try:
        os.unlink(SERVER_LOG)
    except FileNotFoundError:
        pass

    with tempfile.TemporaryDirectory() as tmpdir:
        git_run(["git", "init", "-b", "master"], tmpdir)
        git_run(["git", "config", "user.name", "Test User"], tmpdir)
        git_run(["git", "config", "user.email", "test@example.com"], tmpdir)

        with open(os.path.join(tmpdir, "index.html"), "w") as f:
            f.write(first_string)
        git_run(["git", "add", "index.html"], tmpdir)
        git_run(["git", "commit", "-m", "First deployment"], tmpdir)
        git_run(["git", "remote", "add", "deploy", DEPLOY_GIT], tmpdir)

        # Force only accommodates a repository the administrator may have tested already.
        push = subprocess.run(
            ["git", "push", "deploy", "+master:master"],
            cwd=tmpdir,
            capture_output=True,
            timeout=20,
        )
        assert push.returncode == 0, f"Git push failed: {push.stderr.decode(errors='replace')}"

        first_pid = wait_for_replacement(initial_servers)
        live_file = os.path.join(LIVE_DIR, "index.html")
        assert os.path.isfile(live_file), f"Deployed file not found at {live_file}."
        with open(live_file, "r") as f:
            content = f.read().strip()
        assert content == first_string, f"Deployed file content mismatch: {content!r}"
        wait_for_http(f"http://localhost:8080/index.html?{uuid.uuid4().hex}", first_string)
        wait_for_http(f"http://localhost:8081/index.html?{uuid.uuid4().hex}", first_string)

        # A subsequent push must terminate the hook-started server and start a new one.
        with open(os.path.join(tmpdir, "index.html"), "w") as f:
            f.write(second_string)
        git_run(["git", "add", "index.html"], tmpdir)
        git_run(["git", "commit", "-m", "Second deployment"], tmpdir)
        push = subprocess.run(
            ["git", "push", "deploy", "master:master"],
            cwd=tmpdir,
            capture_output=True,
            timeout=20,
        )
        assert push.returncode == 0, f"Second Git push failed: {push.stderr.decode(errors='replace')}"

        second_pid = wait_for_replacement({first_pid})
        assert second_pid != first_pid, "The HTTP server was not restarted on the second push."
        assert not process_is_active(first_pid), f"Previous HTTP server PID {first_pid} is still running."
        with open(live_file, "r") as f:
            content = f.read().strip()
        assert content == second_string, f"Latest code was not checked out: {content!r}"
        wait_for_http(f"http://localhost:8080/index.html?{uuid.uuid4().hex}", second_string)
        wait_for_http(f"http://localhost:8081/index.html?{uuid.uuid4().hex}", second_string)


def test_server_log_exists():
    """Verify that requests to the hook-started server produced log output."""
    assert os.path.isfile(SERVER_LOG), f"{SERVER_LOG} does not exist."
    assert os.path.getsize(SERVER_LOG) > 0, f"{SERVER_LOG} is empty."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
