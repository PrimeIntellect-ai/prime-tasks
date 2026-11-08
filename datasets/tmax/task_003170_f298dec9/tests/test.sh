#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import signal
import socket
import subprocess
import time
import pytest

MONITOR = "/home/user/vault_monitor.py"
EXPECT_SCRIPT = "/home/user/simulate_uploads.exp"
UPLOADER = "/home/user/interactive_uploader.py"
VAULT = "/home/user/vault"
PID_FILE = "/home/user/monitor.pid"
LOG_FILE = "/home/user/vault_state.log"
QUOTA = 10485760
PORT = 8443


def process_alive(pid):
    try:
        os.kill(pid, 0)
        with open(f"/proc/{pid}/stat", "r") as f:
            return f.read().split()[2] != "Z"
    except (OSError, IOError, IndexError):
        return False


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def terminate_pid(pid):
    if pid <= 1 or pid == os.getpid() or not process_alive(pid):
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    end = time.time() + 2
    while time.time() < end and process_alive(pid):
        time.sleep(0.05)
    if process_alive(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def listener_inodes():
    found = []
    for path, family in (("/proc/net/tcp", "tcp"), ("/proc/net/tcp6", "tcp6")):
        try:
            with open(path, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            address, port_hex = local.rsplit(":", 1)
            if state == "0A" and int(port_hex, 16) == PORT:
                found.append((family, address.upper(), fields[9]))
    return found


def owners_of_inode(inode):
    owners = set()
    target = f"socket:[{inode}]"
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == target:
                        owners.add(int(entry))
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def clean_old_processes():
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid in (1, me, os.getppid()):
            continue
        command = cmdline(pid)
        if MONITOR in command or UPLOADER in command or EXPECT_SCRIPT in command:
            terminate_pid(pid)

    for _, _, inode in listener_inodes():
        for pid in owners_of_inode(inode):
            if pid not in (1, me, os.getppid()):
                terminate_pid(pid)


def reset_vault():
    if os.path.exists(VAULT):
        shutil.rmtree(VAULT)
    os.makedirs(VAULT)
    try:
        os.remove(LOG_FILE)
    except FileNotFoundError:
        pass


def read_pid(timeout=5):
    end = time.time() + timeout
    while time.time() < end:
        try:
            with open(PID_FILE, "r") as f:
                value = f.read().strip()
            if value.isdigit() and process_alive(int(value)):
                return int(value)
        except OSError:
            pass
        time.sleep(0.05)
    pytest.fail("Monitor did not create a valid PID file for a running process")


def status_once():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1.0)
        s.connect(("127.0.0.1", PORT))
        s.sendall(b"STATUS")
        return s.recv(1024).decode("utf-8")


def wait_status(expected, timeout=5):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        try:
            last = status_once()
            if last == expected:
                return
        except (OSError, UnicodeError) as exc:
            last = repr(exc)
        time.sleep(0.1)
    pytest.fail(f"Expected status {expected!r}, last result was {last!r}")


def wait_log(expected, timeout=5):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        try:
            with open(LOG_FILE, "r") as f:
                last = f.read().strip()
            if last == expected:
                return
        except OSError:
            pass
        time.sleep(0.1)
    pytest.fail(f"Expected log {expected!r}, last content was {last!r}")


def write_sized(path, size):
    with open(path, "wb") as f:
        f.truncate(size)


def assert_strict_listener_owned_by(pid):
    listeners = listener_inodes()
    assert listeners, "No TCP listener exists on port 8443"
    assert all(family == "tcp" and address == "0100007F"
               for family, address, _ in listeners), (
        "Port 8443 must be bound strictly to IPv4 127.0.0.1"
    )
    owned = set()
    for _, _, inode in listeners:
        owned.update(owners_of_inode(inode))
    assert pid in owned, f"PID {pid} from monitor.pid does not own the listener"


def test_monitor_and_expect_end_to_end():
    assert os.path.isfile(MONITOR), f"{MONITOR} does not exist or is not a file"
    assert os.path.isfile(EXPECT_SCRIPT), f"{EXPECT_SCRIPT} does not exist or is not a file"

    clean_old_processes()
    reset_vault()
    for path in (PID_FILE,):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    launched = subprocess.Popen(
        ["python3", MONITOR],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    pid = read_pid()
    assert MONITOR in cmdline(pid), "monitor.pid does not identify vault_monitor.py"
    wait_status("OK\n")
    assert_strict_listener_owned_by(pid)

    # Exercise periodic quota calculation on unpredictable file sizes. Exactly
    # the quota must remain unlocked; only a strict excess may lock it.
    first = random.SystemRandom().randint(1000000, QUOTA - 1000000)
    write_sized(os.path.join(VAULT, f"part-{random.getrandbits(64):016x}.bin"), first)
    write_sized(os.path.join(VAULT, f"part-{random.getrandbits(64):016x}.bin"), QUOTA - first)
    time.sleep(1.5)
    assert status_once() == "OK\n", "Vault locked at exactly the quota"

    excess = random.SystemRandom().randint(257, 8192)
    write_sized(os.path.join(VAULT, f"excess-{random.getrandbits(64):016x}.bin"), excess)
    dynamic_total = QUOTA + excess
    wait_log(f"LOCKED: {dynamic_total}")
    wait_status("LOCKED\n")

    # A real uploader process must be found and terminated specifically by
    # SIGTERM while the vault is over quota.
    uploader = subprocess.Popen(
        ["python3", UPLOADER],
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        rc = uploader.wait(timeout=4)
    except subprocess.TimeoutExpired:
        uploader.kill()
        pytest.fail("Monitor did not terminate interactive_uploader.py")
    assert rc == -signal.SIGTERM, f"Uploader exited with {rc}, not from SIGTERM"

    # Return to an under-quota state, then execute the submitted expect script.
    # It must remain active until the daemon detects the resulting breach and
    # kills its uploader child.
    reset_vault()
    wait_status("OK\n")
    exp = subprocess.Popen(
        ["expect", EXPECT_SCRIPT],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 15
    while time.time() < deadline:
        rc = exp.poll()
        log_locked = False
        try:
            with open(LOG_FILE, "r") as f:
                log_locked = f.read().strip() == "LOCKED: 11000000"
        except OSError:
            pass
        uploader_running = any(
            UPLOADER in cmdline(int(entry))
            for entry in os.listdir("/proc") if entry.isdigit()
        )
        if rc is not None:
            assert log_locked and not uploader_running, (
                "Expect script exited before the quota breach killed its uploader"
            )
            break
        time.sleep(0.05)
    else:
        exp.kill()
        pytest.fail("Expect script did not terminate after the monitor killed the uploader")

    wait_log("LOCKED: 11000000")
    wait_status("LOCKED\n")

    # Retain the original final-state assertions.
    assert os.path.exists(PID_FILE), f"{PID_FILE} does not exist."
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID in {PID_FILE} is not a valid integer."
    final_pid = int(pid_str)
    try:
        os.kill(final_pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {final_pid} is not running.")

    assert status_once() == "LOCKED\n"
    assert os.path.isdir(VAULT), f"{VAULT} is not a directory."
    file1 = os.path.join(VAULT, "payload1.bin")
    file2 = os.path.join(VAULT, "payload2.bin")
    assert os.path.exists(file1), f"{file1} does not exist."
    assert os.path.exists(file2), f"{file2} does not exist."
    size1 = os.path.getsize(file1)
    size2 = os.path.getsize(file2)
    assert size1 == 6000000, f"Expected {file1} to be 6000000 bytes, got {size1}"
    assert size2 == 5000000, f"Expected {file2} to be 5000000 bytes, got {size2}"
    assert size1 + size2 == 11000000, "Total size of payload files is not 11000000."

    with open(LOG_FILE, "r") as f:
        content = f.read().strip()
    assert content == "LOCKED: 11000000", f"Unexpected content in {LOG_FILE}: {content}"

    with open(EXPECT_SCRIPT, "r") as f:
        expect_content = f.read()
    assert "spawn" in expect_content, f"spawn command not found in {EXPECT_SCRIPT}"
    assert "expect" in expect_content, f"expect command not found in {EXPECT_SCRIPT}"
    assert "send" in expect_content, f"send command not found in {EXPECT_SCRIPT}"

    output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
    running = False
    for line in output.splitlines():
        if "interactive_uploader.py" in line and "grep" not in line and "simulate_uploads.exp" not in line:
            running = True
            break
    assert not running, "interactive_uploader.py is still running, it should have been killed."


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
