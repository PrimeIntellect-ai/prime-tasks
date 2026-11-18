#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import signal
import subprocess
import time

import pytest

SETUP = "/home/user/setup_env.sh"
REPO = "/home/user/project.git"
HOOK = "/home/user/project.git/hooks/post-receive"
MONITOR = "/home/user/monitor.py"
LOG = "/home/user/deploy.log"
ROTATED = "/home/user/deploy.log.1"
STATUS = "/home/user/monitor_status.txt"
CLONE = "/home/user/dummy_clone"
ENTRY_RE = re.compile(rb"^DEPLOYED: (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\n$")
STATE = {}


def monitor_pids():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                args = [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
            if MONITOR in args:
                found.append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found


def hook_ready():
    return os.path.isfile(HOOK) and os.access(HOOK, os.X_OK)


def read_entries(path):
    with open(path, "rb") as f:
        data = f.read()
    lines = data.splitlines(keepends=True)
    assert lines, f"{path} contains no deployment entries"
    for line in lines:
        match = ENTRY_RE.fullmatch(line)
        assert match, f"Invalid deployment entry in {path}: {line!r}"
        stamp = datetime.datetime.strptime(match.group(1).decode(), "%Y-%m-%d %H:%M:%S").replace(
            tzinfo=datetime.timezone.utc
        )
        delta = abs((datetime.datetime.now(datetime.timezone.utc) - stamp).total_seconds())
        assert delta < 20, f"Timestamp {stamp!s} is not a current UTC timestamp"
    return lines


def push_change(number):
    test_file = os.path.join(CLONE, "test.txt")
    with open(test_file, "w") as f:
        f.write(f"test-{number}-{os.urandom(8).hex()}\n")
    subprocess.run(["git", "add", "test.txt"], cwd=CLONE, check=True)
    subprocess.run(["git", "commit", "-m", f"commit {number}"], cwd=CLONE, check=True)
    env = os.environ.copy()
    # A non-UTC process timezone ensures the hook cannot merely use local time.
    env["TZ"] = "Pacific/Honolulu"
    subprocess.run(["git", "push", "origin", "main"], cwd=CLONE, env=env, check=True)


@pytest.fixture(scope="session", autouse=True)
def run_verification():
    assert os.path.isfile(SETUP), f"{SETUP} does not exist."

    for pid in monitor_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    subprocess.run(["rm", "-rf", REPO, CLONE], check=True)
    for path in (LOG, ROTATED, STATUS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Observe setup so the monitor cannot be started before the hook is ready.
    setup_proc = subprocess.Popen(["bash", SETUP])
    saw_monitor = False
    while setup_proc.poll() is None:
        pids = monitor_pids()
        if pids:
            saw_monitor = True
            assert hook_ready(), "monitor.py was started before the post-receive hook was configured"
        time.sleep(0.01)
    assert setup_proc.returncode == 0, "setup_env.sh failed"
    assert hook_ready(), "post-receive hook was not fully configured"

    live_monitors = monitor_pids()
    saw_monitor = saw_monitor or bool(live_monitors)
    assert saw_monitor, "setup_env.sh did not start monitor.py"
    assert live_monitors, "monitor.py was not running continuously after setup"
    STATE["monitor_pids"] = set(live_monitors)

    # Remove any outputs fabricated by setup; the running monitor and hook must
    # now produce them in response to the actual pushes.
    for path in (LOG, ROTATED, STATUS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    time.sleep(0.8)
    assert not os.path.exists(STATUS), "monitor wrote STATUS: OK without a DEPLOYED: entry"
    assert monitor_pids(), "monitor terminated before detecting a deployment"

    subprocess.run(["git", "clone", REPO, CLONE], check=True)
    subprocess.run(["git", "config", "user.name", "Tester"], cwd=CLONE, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=CLONE, check=True)
    subprocess.run(["git", "checkout", "-b", "main"], cwd=CLONE, check=True)

    push_change(1)
    deadline = time.time() + 3
    while time.time() < deadline and not os.path.exists(STATUS):
        time.sleep(0.05)
    assert os.path.isfile(STATUS), "monitor did not detect the hook's deployment entry"
    assert open(STATUS, "rb").read() == b"STATUS: OK\n"
    assert read_entries(LOG) and len(read_entries(LOG)) == 1
    assert not os.path.exists(ROTATED), "log rotated when its previous size was not greater than 50 bytes"

    deadline = time.time() + 2
    while time.time() < deadline and any(pid in monitor_pids() for pid in STATE["monitor_pids"]):
        time.sleep(0.05)
    assert not any(pid in monitor_pids() for pid in STATE["monitor_pids"]), "monitor did not terminate cleanly"

    push_change(2)
    assert len(read_entries(LOG)) == 2
    assert not os.path.exists(ROTATED), "log rotated before the existing log exceeded 50 bytes"

    push_change(3)
    time.sleep(0.1)
    STATE["rotated_entries"] = read_entries(ROTATED)
    STATE["current_entries"] = read_entries(LOG)


def test_git_server_initialization():
    repo_dir = REPO
    assert os.path.isdir(repo_dir), f"Bare repository directory {repo_dir} not found."
    assert os.path.isfile(os.path.join(repo_dir, "config")), "Git config not found in bare repo."
    result = subprocess.run(["git", "config", "--get", "core.bare"], cwd=repo_dir, capture_output=True, text=True)
    assert result.stdout.strip() == "true", "Repository is not configured as bare."


def test_post_receive_hook_exists_and_executable():
    assert os.path.isfile(HOOK), f"Hook script {HOOK} not found."
    assert os.access(HOOK, os.X_OK), f"Hook script {HOOK} is not executable."
    with open(HOOK, "rb") as f:
        first_line = f.readline().lower()
    assert first_line.startswith(b"#!") and b"python" in first_line, "post-receive must be an executable Python script"
    subprocess.run(["python3", "-m", "py_compile", HOOK], check=True)


def test_monitor_status_output():
    assert os.path.isfile(MONITOR), f"Monitor script {MONITOR} not found."
    subprocess.run(["python3", "-m", "py_compile", MONITOR], check=True)
    assert os.path.isfile(STATUS), f"Monitor status file {STATUS} not found. Monitor may not have run or failed."
    with open(STATUS, "r") as f:
        content = f.read().strip()
    assert content == "STATUS: OK", f"Expected 'STATUS: OK' in {STATUS}, got '{content}'"
    assert open(STATUS, "rb").read() == b"STATUS: OK\n"


def test_log_rotation_and_size():
    assert os.path.isfile(ROTATED), f"Rotated log file {ROTATED} not found. Rotation did not occur."
    assert os.path.isfile(LOG), f"Current log file {LOG} not found."

    rotated_size = os.path.getsize(ROTATED)
    assert rotated_size >= 60, f"Rotated log file size is {rotated_size} bytes, expected at least 60 bytes."
    current_size = os.path.getsize(LOG)
    assert current_size == 30, f"Current log file size is {current_size} bytes, expected exactly 30 bytes."

    assert len(STATE["rotated_entries"]) == 2, "rotated log must contain exactly the first two deployment entries"
    assert len(STATE["current_entries"]) == 1, "current log must contain exactly the third deployment entry"


def test_rotation_uses_actual_strict_size_threshold():
    # Use unpredictable contents so fixed, pre-created log files cannot satisfy
    # the verifier. A 67-byte existing log must rotate.
    payload = os.urandom(67)
    old_rotated = os.urandom(23)
    with open(LOG, "wb") as f:
        f.write(payload)
    with open(ROTATED, "wb") as f:
        f.write(old_rotated)
    push_change(4)
    assert open(ROTATED, "rb").read() == payload, "hook did not overwrite .1 with the actual oversized log"
    entries = read_entries(LOG)
    assert len(entries) == 1, "hook did not start a fresh log after rotation"

    # Exactly 50 bytes must not rotate because the threshold is strictly greater.
    fifty = os.urandom(50)
    saved_rotated = open(ROTATED, "rb").read()
    with open(LOG, "wb") as f:
        f.write(fifty)
    push_change(5)
    assert open(ROTATED, "rb").read() == saved_rotated, "hook rotated a log whose size was exactly 50 bytes"
    current = open(LOG, "rb").read()
    assert current.startswith(fifty), "hook replaced rather than appended to a 50-byte log"
    appended = current[len(fifty):]
    assert ENTRY_RE.fullmatch(appended), f"hook did not append a correctly formatted deployment entry: {appended!r}"
    stamp = datetime.datetime.strptime(ENTRY_RE.fullmatch(appended).group(1).decode(), "%Y-%m-%d %H:%M:%S").replace(
        tzinfo=datetime.timezone.utc
    )
    assert abs((datetime.datetime.now(datetime.timezone.utc) - stamp).total_seconds()) < 20
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
