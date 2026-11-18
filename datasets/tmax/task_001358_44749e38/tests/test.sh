#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import socket
import subprocess
from datetime import datetime, timezone, timedelta
import pytest

HOST = "127.0.0.1"
PORT = 8888
SERVER = "/home/user/server"
SUPERVISOR = "/home/user/supervisor.sh"


def send_command(cmd: str) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2.0)
        s.connect((HOST, PORT))
        s.sendall(cmd.encode("utf-8"))
        response = s.recv(1024).decode("utf-8")
    return response


def get_frame_count() -> int:
    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-count_packets", "-show_entries", "stream=nb_read_packets",
        "-of", "csv=p=0", "/app/surveillance.mp4"
    ]
    output = subprocess.check_output(cmd, text=True).strip()
    return int(output)


def process_identity(pid):
    try:
        data = open(f"/proc/{pid}/stat", "r").read().strip()
        fields_after_comm = data[data.rfind(")") + 2:].split()
        return (int(pid), fields_after_comm[19])  # PID and kernel start time
    except (OSError, ValueError, IndexError):
        return None


def parent_pid(pid):
    try:
        with open(f"/proc/{pid}/status", "r") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (OSError, ValueError, IndexError):
        pass
    return 0


def cmdline(pid):
    try:
        raw = open(f"/proc/{pid}/cmdline", "rb").read()
        return [x.decode("utf-8", "replace") for x in raw.split(b"\0") if x]
    except OSError:
        return []


def listener_inodes():
    result = set()
    try:
        with open("/proc/net/tcp", "r") as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address = fields[1]
                state = fields[3]
                if local_address == "0100007F:22B8" and state == "0A":
                    result.add(fields[9])
    except OSError:
        pass
    return result


def listener_pids():
    inodes = listener_inodes()
    owners = set()
    if not inodes:
        return owners
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(name))
                    break
        except OSError:
            continue
    return owners


def get_server_listener_pid():
    matching = []
    for pid in listener_pids():
        try:
            if os.path.samefile(f"/proc/{pid}/exe", SERVER):
                matching.append(pid)
        except OSError:
            pass
    assert len(matching) == 1, (
        f"Expected exactly one {SERVER} process listening on {HOST}:{PORT}; "
        f"found {matching} (all listener owners: {sorted(listener_pids())})."
    )
    return matching[0]


def find_supervisor_ancestor(server_pid):
    seen = set()
    pid = server_pid
    while pid > 1 and pid not in seen:
        seen.add(pid)
        pid = parent_pid(pid)
        if pid <= 1:
            break
        if SUPERVISOR in cmdline(pid):
            return pid
    return None


def read_environment(pid):
    raw = open(f"/proc/{pid}/environ", "rb").read()
    return dict(
        item.split(b"=", 1)
        for item in raw.split(b"\0")
        if b"=" in item
    )


def test_files_exist():
    assert os.path.isfile("/home/user/server.c"), "/home/user/server.c does not exist."
    assert os.path.isfile(SERVER), "/home/user/server does not exist."
    assert os.path.isfile(SUPERVISOR), "/home/user/supervisor.sh does not exist."


def test_elf_hardening():
    server_path = SERVER

    readelf_h = subprocess.check_output(["readelf", "-h", server_path], text=True)
    assert "DYN (Shared object file)" in readelf_h or "DYN (Position-Independent Executable" in readelf_h, "Executable is not built with PIE."

    readelf_l = subprocess.check_output(["readelf", "-l", server_path], text=True)
    assert "GNU_RELRO" in readelf_l, "Executable is missing RELRO."

    readelf_d = subprocess.check_output(["readelf", "-d", server_path], text=True)
    assert "BIND_NOW" in readelf_d or "FLAGS_1" in readelf_d and "NOW" in readelf_d, "Executable is missing Full RELRO (-z now)."

    readelf_s = subprocess.check_output(["readelf", "-s", server_path], text=True)
    assert "__stack_chk_fail" in readelf_s, "Executable is missing stack protector."


def test_supervisor_running():
    ps_output = subprocess.check_output(["ps", "aux"], text=True)
    assert "supervisor.sh" in ps_output, "supervisor.sh is not running in the background."

    server_pid = get_server_listener_pid()
    supervisor_pid = find_supervisor_ancestor(server_pid)
    assert supervisor_pid is not None, (
        "The process listening on port 8888 is not a child of a running "
        "/home/user/supervisor.sh process."
    )
    assert process_identity(supervisor_pid) is not None, "Supervisor process is not alive."

    environment = read_environment(server_pid)
    assert environment.get(b"TZ") == b"Asia/Tokyo", (
        "The running server was not launched with TZ=Asia/Tokyo by the supervisor."
    )


def test_server_count():
    expected_count = get_frame_count()
    response = send_command("COUNT\n")
    assert response == f"{expected_count}\n", f"Expected COUNT response '{expected_count}\\n', got '{response}'"


def test_server_time():
    before = time.time()
    response = send_command("TIME\n")
    after = time.time()

    pattern = r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} JST\n$"
    assert re.match(pattern, response), f"TIME response '{response}' does not match expected format."

    rendered = datetime.strptime(response.rstrip("\n"), "%Y-%m-%d %H:%M:%S JST")
    rendered = rendered.replace(tzinfo=timezone(timedelta(hours=9)))
    rendered_epoch = rendered.timestamp()
    assert before - 1.0 <= rendered_epoch <= after + 1.0, (
        f"TIME response '{response.rstrip()}' is not the current time in JST."
    )


def test_server_crash_and_restart():
    old_pid = get_server_listener_pid()
    old_identity = process_identity(old_pid)
    assert old_identity is not None

    supervisor_pid = find_supervisor_ancestor(old_pid)
    assert supervisor_pid is not None, "Server is not supervised before CRASH."
    supervisor_identity = process_identity(supervisor_pid)
    assert supervisor_identity is not None

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2.0)
        s.connect((HOST, PORT))
        s.sendall(b"CRASH\n")
        sent_at = time.monotonic()
        try:
            s.recv(1024)
        except (socket.timeout, ConnectionResetError, EOFError):
            pass

    deadline = sent_at + 1.20
    while time.monotonic() < deadline and process_identity(old_pid) == old_identity:
        time.sleep(0.02)
    assert process_identity(old_pid) != old_identity, (
        "CRASH closed the connection but the server process did not exit."
    )

    new_pid = None
    while time.monotonic() < deadline:
        candidates = []
        for pid in listener_pids():
            try:
                if os.path.samefile(f"/proc/{pid}/exe", SERVER):
                    candidates.append(pid)
            except OSError:
                pass
        if len(candidates) == 1 and process_identity(candidates[0]) != old_identity:
            new_pid = candidates[0]
            break
        time.sleep(0.02)

    assert new_pid is not None, "Supervisor did not restart the server within 1 second after CRASH."
    assert process_identity(supervisor_pid) == supervisor_identity, (
        "The original supervisor did not remain alive to perform the restart."
    )
    assert find_supervisor_ancestor(new_pid) == supervisor_pid, (
        "The replacement server was not launched by the original supervisor."
    )
    assert read_environment(new_pid).get(b"TZ") == b"Asia/Tokyo", (
        "The restarted server does not have TZ=Asia/Tokyo."
    )

    time.sleep(max(0, sent_at + 1.5 - time.monotonic()))
    expected_count = get_frame_count()
    try:
        response = send_command("COUNT\n")
        assert response == f"{expected_count}\n", f"Expected COUNT response '{expected_count}\\n' after restart, got '{response}'"
    except ConnectionRefusedError:
        pytest.fail("Server did not restart after CRASH command.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
