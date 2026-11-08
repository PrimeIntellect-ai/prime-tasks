#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import re
import pytest

AUDIT_LOG_PATH = "/home/user/vault/audit.log"
MASTER_KEY_PATH = "/home/user/vault/config/master.key"

def test_audit_log_exists():
    """Check if the audit log exists."""
    assert os.path.isfile(AUDIT_LOG_PATH), f"FAIL: {AUDIT_LOG_PATH} does not exist."

def test_master_key_state():
    """Check if the master.key exists, has correct content, and correct restored permissions (0600)."""
    assert os.path.isfile(MASTER_KEY_PATH), f"FAIL: {MASTER_KEY_PATH} does not exist."

    with open(MASTER_KEY_PATH, "r") as f:
        content = f.read().strip()
    assert content == "SECRET_KEY_DATA", f"FAIL: {MASTER_KEY_PATH} content is incorrect."

    st = os.stat(MASTER_KEY_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"FAIL: {MASTER_KEY_PATH} does not have 0600 permissions. Got: {oct(perms)}"

def test_audit_log_contents():
    """Check the audit log contents for exact sequence of LOCKED and UNLOCKED and idempotency."""
    assert os.path.isfile(AUDIT_LOG_PATH), f"FAIL: {AUDIT_LOG_PATH} does not exist."

    with open(AUDIT_LOG_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"FAIL: audit.log contains extra lines. Expected exactly 2 non-empty lines, found {len(lines)}."

    locked_pattern = re.compile(r"^LOCKED \d{10,}$")
    unlocked_pattern = re.compile(r"^UNLOCKED \d{10,}$")

    assert locked_pattern.match(lines[0]), f"FAIL: First line of audit.log does not match expected LOCKED format. Got: '{lines[0]}'"
    assert unlocked_pattern.match(lines[1]), f"FAIL: Second line of audit.log does not match expected UNLOCKED format. Got: '{lines[1]}'"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_watchdog_behavior.py
import os
import re
import shutil
import signal
import stat
import subprocess
import time

SCRIPT = "/home/user/watchdog.sh"
VAULT = "/home/user/vault"
DATA = os.path.join(VAULT, "data")
CONFIG = os.path.join(VAULT, "config")
KEY = os.path.join(CONFIG, "master.key")
AUDIT = os.path.join(VAULT, "audit.log")
STATE = os.path.join(VAULT, ".lockdown")
PAYLOAD = os.path.join(DATA, "verifier-quota-test.bin")
EVENT_RE = re.compile(r"^(LOCKED|UNLOCKED) (\d{10,})$")


def audit_lines():
    if not os.path.isfile(AUDIT):
        return []
    with open(AUDIT, "r") as f:
        return [line.strip() for line in f if line.strip()]


def wait_for(predicate, timeout, message):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    raise AssertionError(message)


def process_alive(proc):
    return proc.poll() is None


def has_sleep_two(pid):
    children_path = f"/proc/{pid}/task/{pid}/children"
    try:
        with open(children_path, "r") as f:
            children = f.read().split()
    except OSError:
        return False
    for child in children:
        try:
            with open(f"/proc/{child}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except OSError:
            continue
        if args and os.path.basename(args[0]) == "sleep" and len(args) >= 2:
            if args[1] in ("2", "2s", "2.0"):
                return True
    return False


def existing_watchdogs():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except OSError:
            continue
        if SCRIPT in args:
            found.append(int(name))
    return found


def disk_usage_kb():
    output = subprocess.check_output(["du", "-sk", DATA], text=True)
    return int(output.split()[0])


def event(line, expected_kind):
    match = EVENT_RE.fullmatch(line)
    assert match, f"Malformed audit event: {line!r}"
    assert match.group(1) == expected_kind, f"Expected {expected_kind}, got {line!r}"
    return int(match.group(2))


assert os.path.isfile(SCRIPT), f"Missing watchdog script: {SCRIPT}"
assert not os.path.islink(SCRIPT), "watchdog.sh must be a real script, not a symlink"
assert stat.S_ISREG(os.stat(SCRIPT).st_mode), "watchdog.sh is not a regular file"
assert os.access(SCRIPT, os.X_OK), "watchdog.sh is not executable"
subprocess.run(["bash", "-n", SCRIPT], check=True)
assert not existing_watchdogs(), "A watchdog process was left running instead of being killed"
assert os.path.isdir(DATA), f"Missing data directory: {DATA}"
assert os.path.isdir(CONFIG), f"Missing config directory: {CONFIG}"

for entry in os.listdir(DATA):
    path = os.path.join(DATA, entry)
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)
for path in (AUDIT, STATE):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass

assert os.path.isfile(KEY), f"Missing master key: {KEY}"
with open(KEY, "r") as f:
    assert f.read().strip() == "SECRET_KEY_DATA", "master.key content changed"
os.chmod(KEY, 0o600)
assert disk_usage_kb() <= 2048, "Verifier could not establish a below-quota baseline"

proc = None
try:
    proc = subprocess.Popen(
        [SCRIPT],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for(lambda: not process_alive(proc) or has_sleep_two(proc.pid), 4.0,
             "watchdog did not demonstrate a two-second sleep between iterations")
    assert process_alive(proc), "watchdog exited instead of running continuously"
    assert audit_lines() == [], "watchdog logged an event while usage was below quota"
    assert not os.path.exists(STATE), "watchdog created lockdown state below quota"

    with open(PAYLOAD, "wb") as f:
        block = b"\0" * (1024 * 1024)
        for _ in range(3):
            f.write(block)
        f.flush()
        os.fsync(f.fileno())
    assert disk_usage_kb() > 2048, "Verifier payload did not exceed the quota"
    lock_trigger = int(time.time())

    wait_for(lambda: len(audit_lines()) >= 1, 7.0,
             "watchdog did not log a lockdown after usage exceeded 2048 KB")
    assert process_alive(proc), "watchdog exited during lockdown"
    lines = audit_lines()
    assert len(lines) == 1, f"Expected one lockdown event, got {lines!r}"
    locked_ts = event(lines[0], "LOCKED")
    assert lock_trigger - 1 <= locked_ts <= int(time.time()) + 1, "LOCKED timestamp was not generated by this transition"
    assert stat.S_IMODE(os.stat(KEY).st_mode) == 0o400, "master.key was not changed to 0400"
    assert os.path.isfile(STATE), "lockdown state file was not created"
    key_locked_ctime = os.stat(KEY).st_ctime_ns
    state_mtime = os.stat(STATE).st_mtime_ns

    time.sleep(3.2)
    assert process_alive(proc), "watchdog did not continue looping while locked"
    assert audit_lines() == lines, "watchdog repeatedly logged LOCKED while already locked"
    assert os.stat(KEY).st_ctime_ns == key_locked_ctime, "watchdog repeatedly attempted to chmod an already locked key"
    assert os.stat(STATE).st_mtime_ns == state_mtime, "watchdog repeatedly rewrote the lockdown state"

    os.unlink(PAYLOAD)
    assert disk_usage_kb() <= 2048, "Usage did not return below the quota"
    unlock_trigger = int(time.time())

    wait_for(lambda: len(audit_lines()) >= 2, 7.0,
             "watchdog did not log an unlock after usage returned below 2048 KB")
    assert process_alive(proc), "watchdog exited during unlock"
    lines = audit_lines()
    assert len(lines) == 2, f"Expected exactly two transition events, got {lines!r}"
    unlocked_ts = event(lines[1], "UNLOCKED")
    assert unlock_trigger - 1 <= unlocked_ts <= int(time.time()) + 1, "UNLOCKED timestamp was not generated by this transition"
    assert unlocked_ts >= locked_ts, "UNLOCKED timestamp precedes LOCKED timestamp"
    assert stat.S_IMODE(os.stat(KEY).st_mode) == 0o600, "master.key was not restored to 0600"
    assert not os.path.exists(STATE), "lockdown state file was not cleared"
    key_unlocked_ctime = os.stat(KEY).st_ctime_ns

    time.sleep(3.2)
    assert process_alive(proc), "watchdog did not continue looping after unlock"
    assert audit_lines() == lines, "watchdog logged extra events without another transition"
    assert os.stat(KEY).st_ctime_ns == key_unlocked_ctime, "watchdog repeatedly attempted to chmod after unlock"
finally:
    if proc is not None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=3)
    try:
        os.unlink(PAYLOAD)
    except FileNotFoundError:
        pass
DYNAMIC_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_watchdog_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
