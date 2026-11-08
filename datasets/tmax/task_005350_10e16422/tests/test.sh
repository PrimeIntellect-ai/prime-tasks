#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import tempfile
import uuid
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import pytest

GIT = "/usr/bin/git"
BARE = "/home/user/bare_repo.git"
PROXY_URL = "git://127.0.0.1:8080/"
DIRECT_URL = "git://127.0.0.1:9418/"
LOG = "/home/user/restore_log.txt"
LOG_RE = re.compile(r"^RESTORE_PUSH: ([0-9a-f]{40}) at (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})$")


def git(*args, cwd=None, timeout=20):
    return subprocess.check_output(
        [GIT, *args], cwd=cwd, text=True, stderr=subprocess.STDOUT,
        timeout=timeout
    ).strip()


def test_bare_repo_exists():
    """Verify that the bare repository exists and is properly initialized."""
    assert os.path.isdir(BARE), f"Bare repository directory {BARE} does not exist."
    assert os.path.isfile(os.path.join(BARE, "HEAD")), "Bare repository is missing HEAD file."
    assert os.path.isdir(os.path.join(BARE, "objects")), "Bare repository is missing objects directory."
    assert git("rev-parse", "--is-bare-repository", cwd=BARE) == "true"


def test_extracted_backup_is_present_and_imported():
    extracted_repo = "/home/user/extracted/source_repo"
    assert os.path.isdir(extracted_repo), "The backup was not extracted to /home/user/extracted/source_repo."
    extracted_head = git("rev-parse", "HEAD", cwd=extracted_repo)
    assert re.fullmatch(r"[0-9a-f]{40}", extracted_head)
    subprocess.check_call(
        [GIT, "cat-file", "-e", extracted_head + "^{commit}"], cwd=BARE,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    subprocess.check_call(
        [GIT, "merge-base", "--is-ancestor", extracted_head, "HEAD"], cwd=BARE,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def test_symlink_correct():
    """Verify that the symlink for the restore environment is correct."""
    symlink_path = "/home/user/restore_env/current_repo"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    target = os.readlink(symlink_path)
    assert target == BARE, f"Symlink points to {target} instead of {BARE}"


def check_port_open(port):
    """Helper to check if a local port is listening."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2)
        return s.connect_ex(("127.0.0.1", port)) == 0


def read_pid(path):
    assert os.path.isfile(path), f"{path} does not exist."
    text = open(path, encoding="utf-8").read().strip()
    assert re.fullmatch(r"[1-9][0-9]*", text), f"{path} does not contain a valid PID."
    pid = int(text)
    assert os.path.isdir(f"/proc/{pid}"), f"PID {pid} from {path} is not running."
    return pid


def listening_inodes(port):
    wanted = f"0100007F:{port:04X}"
    inodes = set()
    with open("/proc/net/tcp", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    return inodes


def pid_owns_listener(pid, port):
    inodes = listening_inodes(port)
    if not inodes:
        return False
    fd_dir = f"/proc/{pid}/fd"
    try:
        for name in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, name))
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[([0-9]+)\]", target)
            if match and match.group(1) in inodes:
                return True
    except OSError:
        return False
    return False


def remote_head(url):
    output = git("ls-remote", url, "HEAD", timeout=15)
    match = re.fullmatch(r"([0-9a-f]{40})\s+HEAD", output)
    assert match, f"{url} did not provide a valid Git HEAD response: {output!r}"
    return match.group(1)


def test_services_running():
    """Verify that the PID files identify the listeners and both endpoints speak Git."""
    daemon_pid = read_pid("/home/user/git_daemon.pid")
    proxy_pid = read_pid("/home/user/proxy.pid")
    assert daemon_pid != proxy_pid, "Git daemon and proxy PID files identify the same process."

    assert check_port_open(9418), "Git daemon port 9418 is not listening on 127.0.0.1"
    assert check_port_open(8080), "Proxy port 8080 is not listening on 127.0.0.1"
    assert pid_owns_listener(daemon_pid, 9418), "git_daemon.pid does not identify the port 9418 listener."
    assert pid_owns_listener(proxy_pid, 8080), "proxy.pid does not identify the port 8080 listener."

    cmdline = open(f"/proc/{daemon_pid}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "replace").lower()
    assert "git" in cmdline and "daemon" in cmdline, f"PID {daemon_pid} is not a git daemon: {cmdline!r}"

    bare_head = git("rev-parse", "HEAD", cwd=BARE)
    assert remote_head(DIRECT_URL) == bare_head, "Port 9418 is not serving the restored bare repository."
    assert remote_head(PROXY_URL) == bare_head, "Port 8080 does not forward to the restored Git service."


def test_test_clone_and_file():
    """Verify that the test clone contains a committed file which was pushed to the bare repository."""
    clone_path = "/home/user/test_clone"
    file_path = os.path.join(clone_path, "restore_verified.txt")

    assert os.path.isdir(os.path.join(clone_path, ".git")), f"{clone_path} is not a valid git repository."
    assert os.path.isfile(file_path), f"{file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()
    assert content == "RESTORE OK", f"File content is '{content}', expected 'RESTORE OK'."

    clone_head = git("rev-parse", "HEAD", cwd=clone_path)
    bare_head = git("rev-parse", "HEAD", cwd=BARE)
    assert clone_head == bare_head, "The test clone's commit was not pushed to the bare repository."
    assert git("show", "HEAD:restore_verified.txt", cwd=clone_path).strip() == "RESTORE OK"
    assert git("show", "HEAD:restore_verified.txt", cwd=BARE).strip() == "RESTORE OK"


def test_restore_log_format_and_content():
    """Verify that the existing restore log has the correct format and commit hash."""
    assert os.path.isfile(LOG), f"{LOG} does not exist."

    with open(LOG, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, f"{LOG} is empty."
    last_line = lines[-1]
    match = LOG_RE.fullmatch(last_line)
    assert match, f"Log line '{last_line}' does not match the required format."

    logged_hash = match.group(1)
    try:
        bare_hash = git("rev-parse", "HEAD", cwd=BARE)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to get HEAD commit hash from the bare repository.")
    assert logged_hash == bare_hash, f"Logged commit hash {logged_hash} does not match bare repo HEAD {bare_hash}."


def test_proxy_push_executes_hook_with_auckland_time():
    """Perform a fresh push through port 8080 and verify the real post-receive result."""
    hook = os.path.join(BARE, "hooks", "post-receive")
    assert os.path.isfile(hook), "The post-receive hook does not exist."
    assert os.access(hook, os.X_OK), "The post-receive hook is not executable."

    with open(LOG, "r", encoding="utf-8") as f:
        old_lines = f.read().splitlines()

    branch_ref = git("symbolic-ref", "HEAD", cwd=BARE)
    assert branch_ref.startswith("refs/heads/")
    branch = branch_ref[len("refs/heads/"):]

    with tempfile.TemporaryDirectory(prefix="restore-verifier-") as td:
        clone_dir = os.path.join(td, "clone")
        subprocess.check_call([GIT, "clone", PROXY_URL, clone_dir], timeout=30)
        marker = "verifier_" + uuid.uuid4().hex + ".txt"
        with open(os.path.join(clone_dir, marker), "w", encoding="utf-8") as f:
            f.write("hook verification\n")
        subprocess.check_call([GIT, "add", marker], cwd=clone_dir)
        subprocess.check_call([
            GIT, "-c", "user.name=Restore Verifier", "-c", "user.email=verifier@example.invalid",
            "commit", "-m", "Verify restored hook and proxy"
        ], cwd=clone_dir, stdout=subprocess.DEVNULL)
        new_hash = git("rev-parse", "HEAD", cwd=clone_dir)
        before = datetime.now(timezone.utc)
        subprocess.check_call([GIT, "push", "origin", f"HEAD:{branch}"], cwd=clone_dir, timeout=30)
        after = datetime.now(timezone.utc)

    assert git("rev-parse", "HEAD", cwd=BARE) == new_hash, "A push through port 8080 did not update the bare repository."
    with open(LOG, "r", encoding="utf-8") as f:
        new_lines = f.read().splitlines()
    assert new_lines[:len(old_lines)] == old_lines, "The hook overwrote existing restore log entries."
    appended = new_lines[len(old_lines):]
    assert len(appended) == 1, f"The push should append exactly one log line, but appended {len(appended)}."

    match = LOG_RE.fullmatch(appended[0])
    assert match, f"Hook output {appended[0]!r} does not match the required format."
    assert match.group(1) == new_hash, "The hook did not log the commit pushed by the verifier."

    local_naive = datetime.strptime(match.group(2), "%Y-%m-%d %H:%M:%S")
    auckland = ZoneInfo("Pacific/Auckland")
    candidates = [local_naive.replace(tzinfo=auckland, fold=fold).astimezone(timezone.utc) for fold in (0, 1)]
    assert any(before.timestamp() - 5 <= value.timestamp() <= after.timestamp() + 5 for value in candidates), \
        f"Timestamp {match.group(2)!r} was not the current Pacific/Auckland time."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
