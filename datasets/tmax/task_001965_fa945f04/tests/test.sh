#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import socket
import stat
import subprocess
import tempfile
import time

HOST = "127.0.0.1"
PORT = 8844
TOKEN = "SEC-99-BKUP-X7"
SOURCE = "/home/user/backup_daemon.c"
SCRIPT = "/home/user/manage_backup.sh"
BINARY = "/home/user/backup_daemon"
PIDFILE = "/home/user/backup_daemon.pid"
BACKUP_DIR = "/home/user/backups"


def send_request(data: bytes, fragmented=False) -> bytes:
    with socket.create_connection((HOST, PORT), timeout=2) as sock:
        sock.settimeout(2)
        if fragmented:
            for byte in data:
                sock.sendall(bytes([byte]))
                time.sleep(0.001)
        else:
            sock.sendall(data)

        response = bytearray()
        while True:
            try:
                chunk = sock.recv(1024)
            except socket.timeout:
                break
            if not chunk:
                break
            response.extend(chunk)
        return bytes(response)


def read_pid() -> int:
    assert os.path.exists(PIDFILE), f"{PIDFILE} is missing."
    raw = open(PIDFILE, "r").read().strip()
    assert raw.isdigit() and int(raw) > 1, f"PID file does not contain a valid daemon PID: {raw!r}"
    return int(raw)


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def assert_daemon_pid(pid: int):
    assert process_alive(pid), f"PID {pid} from PID file is not running"
    exe_link = f"/proc/{pid}/exe"
    assert os.path.exists(exe_link), f"No executable is associated with daemon PID {pid}"
    actual = os.path.realpath(exe_link)
    expected = os.path.realpath(BINARY)
    assert actual == expected, f"PID {pid} runs {actual!r}, not {expected!r}"


def wait_for_port(open_expected: bool, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                is_open = True
        except OSError:
            is_open = False
        if is_open == open_expected:
            return
        time.sleep(0.1)
    state = "open" if open_expected else "closed"
    assert False, f"Port {HOST}:{PORT} did not become {state}"


def snapshot_backups():
    os.makedirs(BACKUP_DIR, exist_ok=True)
    return set(os.listdir(BACKUP_DIR))


def assert_valid_request(payload: str, fragmented=False):
    before = snapshot_backups()
    request = f"TOKEN:{TOKEN}|PAYLOAD:{payload}\n".encode()
    response = send_request(request, fragmented=fragmented)
    assert response == b"OK\n", f"Expected b'OK\\n', got {response!r}"

    deadline = time.time() + 2
    new_files = set()
    while time.time() < deadline:
        new_files = set(os.listdir(BACKUP_DIR)) - before
        if new_files:
            break
        time.sleep(0.05)
    assert new_files, "No new backup file was created in /home/user/backups/"

    found_payload = False
    found_exact = False
    expected = payload.encode()
    for name in new_files:
        path = os.path.join(BACKUP_DIR, name)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            content = handle.read()
        if expected in content:
            found_payload = True
        if content == expected:
            found_exact = True
    assert found_payload, f"The payload {payload!r} was not found in any newly created backup file"
    assert found_exact, f"No newly created backup file contained exactly {payload!r}"


def assert_unauthorized(request: bytes):
    before = snapshot_backups()
    response = send_request(request)
    assert response == b"ERR: Unauthorized\n", f"Expected b'ERR: Unauthorized\\n', got {response!r}"
    time.sleep(0.15)
    after = set(os.listdir(BACKUP_DIR))
    assert after == before, "An unauthorized or malformed request created a backup file"


def run_manager(action: str):
    result = subprocess.run(
        [SCRIPT, action], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == 0, (
        f"manage_backup.sh {action} failed with code {result.returncode}: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_complete_daemon_and_lifecycle():
    # Preserve the original required-file and running-service assertions.
    assert os.path.exists(SOURCE), f"{SOURCE} is missing."
    assert os.path.exists(SCRIPT), f"{SCRIPT} is missing."
    assert os.path.exists(PIDFILE), f"{PIDFILE} is missing."
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"{SOURCE} is not a regular file"
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file"
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable"

    # Independently establish that the submitted C source really compiles.
    with tempfile.TemporaryDirectory() as directory:
        compiled = os.path.join(directory, "backup_daemon")
        result = subprocess.run(
            ["gcc", SOURCE, "-o", compiled], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
        )
        assert result.returncode == 0, f"backup_daemon.c does not compile: {result.stderr}"
        with open(compiled, "rb") as handle:
            assert handle.read(4) == b"\x7fELF", "Compiled source did not produce an ELF executable"

    wait_for_port(True)
    initial_pid = read_pid()
    assert_daemon_pid(initial_pid)

    # Retain the original fixed valid, invalid-token, and malformed interactions.
    assert_valid_request("system_config_v1_backup_test123")
    assert_unauthorized(b"TOKEN:WRONG-TOKEN|PAYLOAD:rogue_data\n")
    assert_unauthorized(b"BADFORMAT\n")

    # Exercise unpredictable payloads and tokens so fixed-response listeners fail.
    for _ in range(3):
        payload = "backup_" + secrets.token_hex(24)
        assert_valid_request(payload, fragmented=True)

    random_payload = "rogue_" + secrets.token_hex(18)
    random_wrong_token = "WRONG-" + secrets.token_hex(20)
    malformed = [
        f"TOKEN:{random_wrong_token}|PAYLOAD:{random_payload}\n".encode(),
        f"TOKEN:{TOKEN}-suffix|PAYLOAD:{random_payload}\n".encode(),
        f"TOKEN:{TOKEN}PAYLOAD:{random_payload}\n".encode(),
        f"TOKEN:{TOKEN}|DATA:{random_payload}\n".encode(),
        ("GARBAGE-" + secrets.token_hex(25) + "\n").encode(),
    ]
    for request in malformed:
        assert_unauthorized(request)

    # Verify stop actually kills the recorded daemon, removes its PID file, and closes the port.
    run_manager("stop")
    deadline = time.time() + 4
    while time.time() < deadline and process_alive(initial_pid):
        time.sleep(0.1)
    assert not process_alive(initial_pid), f"Daemon PID {initial_pid} survived manage_backup.sh stop"
    assert not os.path.exists(PIDFILE), "PID file was not removed by manage_backup.sh stop"
    wait_for_port(False)

    # Force start to compile a fresh executable, then verify that exact executable is launched.
    if os.path.exists(BINARY):
        os.remove(BINARY)
    run_manager("start")
    wait_for_port(True)
    assert os.path.isfile(BINARY), "manage_backup.sh start did not compile /home/user/backup_daemon"
    assert os.access(BINARY, os.X_OK), "Compiled daemon is not executable"
    with open(BINARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "/home/user/backup_daemon is not an ELF executable"

    restarted_pid = read_pid()
    assert_daemon_pid(restarted_pid)
    assert restarted_pid != initial_pid, "start did not launch a new daemon process"

    # Confirm the restarted compiled daemon handles another unpredictable stream.
    assert_valid_request("restart_" + secrets.token_hex(28), fragmented=True)
    assert_unauthorized(
        f"TOKEN:BAD-{secrets.token_hex(16)}|PAYLOAD:{secrets.token_hex(20)}\n".encode()
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
