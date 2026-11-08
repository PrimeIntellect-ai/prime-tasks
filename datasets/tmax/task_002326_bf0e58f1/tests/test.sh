#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import socket
import stat
import subprocess
import tempfile
import time
import uuid

import pytest

DASHBOARD = "/home/user/dashboard"
REPO = "/home/user/metrics-config.git"
HOOK = os.path.join(REPO, "hooks", "post-receive")
ALERTS = os.path.join(DASHBOARD, "alerts.log")
EVENTS = os.path.join(DASHBOARD, "events.log")


def assert_rust_elf(path):
    """Require an executable ELF containing characteristic Rust runtime data."""
    assert os.path.isfile(path), f"Compiled executable not found at {path}"
    assert os.access(path, os.X_OK), f"{path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary"

    result = subprocess.run(
        ["strings", "-a", path], capture_output=True, text=True, errors="replace"
    )
    assert result.returncode == 0, f"Could not inspect compiled binary {path}"
    rust_markers = (
        "/rustc/",
        "library/std/src/",
        "rust_eh_personality",
        "rust_begin_unwind",
        "core::panicking",
        "std::rt::lang_start",
    )
    assert any(marker in result.stdout for marker in rust_markers), (
        f"{path} does not appear to have been compiled from Rust"
    )


def read_from_offset(path, offset):
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as f:
        f.seek(offset)
        return f.read().decode("utf-8", errors="strict")


def file_size(path):
    return os.path.getsize(path) if os.path.exists(path) else 0


def listening_pid():
    """Return the PID owning the IPv4 listener on 127.0.0.1:8025."""
    inode = None
    try:
        with open("/proc/net/tcp", "r") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1] == "0100007F:1F59" and fields[3] == "0A":
                    inode = fields[9]
                    break
    except FileNotFoundError:
        return None

    if inode is None:
        return None

    target = f"socket:[{inode}]"
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == target:
                        return int(entry)
                except (FileNotFoundError, PermissionError, OSError):
                    pass
        except (FileNotFoundError, PermissionError):
            pass
    return None


def wait_for_listener(timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pid = listening_pid()
        if pid is not None:
            return pid
        time.sleep(0.1)
    return None


def assert_listener_is_rust_smtp_alerter():
    pid = wait_for_listener()
    assert pid is not None, "No process is listening on 127.0.0.1:8025"
    exe_link = f"/proc/{pid}/exe"
    try:
        executable = os.path.realpath(exe_link)
        invoked_name = os.path.basename(os.readlink(exe_link)).replace(" (deleted)", "")
    except OSError as exc:
        pytest.fail(f"Could not inspect SMTP listener process {pid}: {exc}")
    assert invoked_name == "smtp-alerter", (
        f"Port 8025 is owned by {invoked_name!r}, not smtp-alerter"
    )
    assert_rust_elf(executable)
    return pid


def send_message(message):
    try:
        with socket.create_connection(("127.0.0.1", 8025), timeout=5) as sock:
            sock.sendall(message.encode("utf-8"))
    except OSError as exc:
        pytest.fail(f"Could not send to smtp-alerter on 127.0.0.1:8025: {exc}")


def wait_for_appended_lines(path, offset, expected, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(path):
            data = read_from_offset(path, offset)
            lines = data.splitlines()
            if all(value in lines for value in expected):
                return lines
        time.sleep(0.1)
    return read_from_offset(path, offset).splitlines() if os.path.exists(path) else []


def test_dashboard_directory_exists():
    assert os.path.isdir(DASHBOARD), "/home/user/dashboard/ directory does not exist."


def test_git_hook_is_compiled_rust_and_handles_dynamic_input():
    assert os.path.isdir(REPO), f"Bare Git repository not found at {REPO}"
    bare = subprocess.run(
        ["git", "--git-dir", REPO, "rev-parse", "--is-bare-repository"],
        capture_output=True,
        text=True,
    )
    assert bare.returncode == 0 and bare.stdout.strip() == "true", (
        f"{REPO} is not a valid bare Git repository"
    )
    assert os.path.isfile(HOOK), f"Git hook not found at {HOOK}"
    assert os.access(HOOK, os.X_OK), f"Git hook at {HOOK} is not executable"
    assert_rust_elf(HOOK)

    fixed_branch = "test-branch-123"
    dynamic_branches = [
        "verify-" + uuid.uuid4().hex,
        "verify-" + uuid.uuid4().hex,
    ]
    branches = [fixed_branch] + dynamic_branches

    # Remove a possible remnant of the old fixed test without invoking the hook.
    subprocess.run(
        ["git", "--git-dir", REPO, "update-ref", "-d", f"refs/heads/{fixed_branch}"],
        check=False,
        capture_output=True,
    )

    offset = file_size(EVENTS)
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "init"], cwd=tmpdir, check=True, capture_output=True)
        subprocess.run(["git", "config", "user.name", "Verifier"], cwd=tmpdir, check=True)
        subprocess.run(["git", "config", "user.email", "verifier@example.invalid"], cwd=tmpdir, check=True)
        subprocess.run(["git", "remote", "add", "origin", REPO], cwd=tmpdir, check=True)
        with open(os.path.join(tmpdir, "testfile.txt"), "w") as f:
            f.write(uuid.uuid4().hex)
        subprocess.run(["git", "add", "testfile.txt"], cwd=tmpdir, check=True)
        subprocess.run(["git", "commit", "-m", "Verifier commit"], cwd=tmpdir, check=True, capture_output=True)

        refspecs = [f"HEAD:refs/heads/{branch}" for branch in branches]
        pushed = subprocess.run(
            ["git", "push", "origin", *refspecs],
            cwd=tmpdir,
            capture_output=True,
            text=True,
        )
        assert pushed.returncode == 0, f"Git push failed: {pushed.stderr}"

    assert os.path.isfile(EVENTS), f"{EVENTS} was not created."
    appended = read_from_offset(EVENTS, offset).splitlines()
    expected = [f'{{"type": "push", "ref": "refs/heads/{branch}"}}' for branch in branches]

    # Retain the original fixed assertion and additionally require exact output
    # for unpredictable refs delivered together in one post-receive invocation.
    assert expected[0] in appended, f"Expected JSON log {expected[0]!r} not found"
    assert collections.Counter(appended) == collections.Counter(expected), (
        f"Hook did not emit one strictly formatted line per input ref. "
        f"Expected {expected!r}, got {appended!r}"
    )


def test_smtp_daemon_is_rust_and_parses_multiple_dynamic_messages():
    assert_listener_is_rust_smtp_alerter()

    fixed_subject = "Critical System Alert Pytest"
    dynamic_one = "alert-" + uuid.uuid4().hex
    dynamic_two = "second alert " + uuid.uuid4().hex
    offset = file_size(ALERTS)

    send_message(
        f"HELO localhost\r\nX-Subject: ignored-{uuid.uuid4().hex}\r\n"
        f"Subject: {fixed_subject}\r\nData\r\nQUIT\r\n"
    )
    send_message(
        f"unrelated line\nSubject: {dynamic_one}\nSubject: {dynamic_two} \t \r\n"
    )

    expected = [fixed_subject, dynamic_one, dynamic_two]
    appended = wait_for_appended_lines(ALERTS, offset, expected)
    assert os.path.isfile(ALERTS), f"{ALERTS} was not created."
    assert fixed_subject in appended, f"Expected subject {fixed_subject!r} not found"
    assert appended == expected, (
        "smtp-alerter did not extract exact Subject values or trim trailing whitespace; "
        f"expected {expected!r}, got {appended!r}"
    )


def test_monitor_script_and_cron():
    monitor_script = "/home/user/monitor.sh"
    assert os.path.isfile(monitor_script), f"{monitor_script} does not exist."
    assert os.access(monitor_script, os.X_OK), f"{monitor_script} is not executable."

    crontab_result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert crontab_result.returncode == 0, "Failed to read crontab."
    assert monitor_script in crontab_result.stdout, f"{monitor_script} not found in crontab."
    cron_lines = [
        line for line in crontab_result.stdout.splitlines()
        if monitor_script in line and not line.strip().startswith("#")
    ]
    assert cron_lines, f"No active cron job found for {monitor_script}."
    cron_parts = cron_lines[0].split()
    assert cron_parts[:5] == ["*", "*", "*", "*", "*"], (
        "Cron job is not configured to run every minute (* * * * *)."
    )


def test_monitor_script_restarts_functional_rust_daemon():
    # Preserve the original process-name restart check, then verify that the
    # restarted process is the actual Rust TCP daemon rather than a decoy.
    subprocess.run(["pkill", "-9", "-f", "smtp-alerter"], check=False)
    deadline = time.time() + 5
    while time.time() < deadline:
        result = subprocess.run(["pgrep", "-f", "smtp-alerter"], capture_output=True)
        if result.returncode != 0:
            break
        time.sleep(0.1)
    result = subprocess.run(["pgrep", "-f", "smtp-alerter"], capture_output=True)
    assert result.returncode != 0, "Failed to kill smtp-alerter for testing."
    assert listening_pid() is None, "Port 8025 remained open after killing smtp-alerter"

    subprocess.run(["/home/user/monitor.sh"], check=True)
    pid = assert_listener_is_rust_smtp_alerter()
    assert pid is not None
    result = subprocess.run(["pgrep", "-f", "smtp-alerter"], capture_output=True)
    assert result.returncode == 0, "monitor.sh failed to restart smtp-alerter."

    restart_subject = "restart-" + uuid.uuid4().hex
    offset = file_size(ALERTS)
    send_message(f"Subject: {restart_subject}\r\nQUIT\r\n")
    appended = wait_for_appended_lines(ALERTS, offset, [restart_subject])
    assert appended == [restart_subject], (
        "The process started by monitor.sh is not a functional smtp-alerter; "
        f"got {appended!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
