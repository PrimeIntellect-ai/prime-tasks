#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import socket
import stat
import subprocess
import time

import pytest

N = 24
HOST = "127.0.0.1"
PORT = 9000
SERVER = "/home/user/server"
SOURCE = "/home/user/server.c"
LOG = "/home/user/pipeline.log"


def listening_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local_address = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    try:
                        port = int(local_address.rsplit(":", 1)[1], 16)
                    except ValueError:
                        continue
                    if port == PORT and state == "0A":
                        inodes.add(inode)
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def same_file_as_server(pid):
    try:
        server_stat = os.stat(SERVER)
        exe_stat = os.stat(f"/proc/{pid}/exe")
        return (server_stat.st_dev, server_stat.st_ino) == (exe_stat.st_dev, exe_stat.st_ino)
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return False


def stop_port():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listening_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.time() + 2
        while time.time() < deadline and listening_pids():
            time.sleep(0.05)
    assert not listening_pids(), f"Could not stop existing listener(s) on port {PORT}"


def connect_when_ready(timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return socket.create_connection((HOST, PORT), timeout=1)
        except OSError as exc:
            last_error = exc
            time.sleep(0.05)
    pytest.fail(f"Could not connect to TCP server at {HOST}:{PORT}: {last_error}")


def make_messages():
    # Preserve the original verifier's sequence, then add unpredictable and
    # substantially varied UTF-8 inputs generated only after the agent exits.
    messages = ["Hello", "こんにちは", "A"]
    messages.extend(chr(97 + (i % 26)) for i in range(27))

    varied = [
        "", "é", "e\u0301", "😀", "漢字かな", "𐍈", "🙂🙃😉",
        "ASCII and Unicode 世界", "नमस्ते", "Здравствуй", "مرحبا"
    ]
    alphabet = list("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    alphabet += list("éøßñ漢字界日😀🚀λЖअم")
    for _ in range(55):
        length = secrets.randbelow(41)
        varied.append("".join(secrets.choice(alphabet) for _ in range(length)))

    # A random ordering prevents a server from relying on a fixed continuation.
    for i in range(len(varied) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        varied[i], varied[j] = varied[j], varied[i]
    messages.extend(varied)
    return messages


def test_video_stats_file():
    path = "/home/user/video_stats.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert content == "24\n", f"Expected '24\\n' in {path}, got {content!r}"


def test_c_artifacts_and_randomized_server_behavior():
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    assert os.path.isfile(SERVER), f"File {SERVER} does not exist."
    mode = os.stat(SERVER).st_mode
    assert stat.S_ISREG(mode), f"{SERVER} is not a regular file."
    assert mode & 0o111, f"{SERVER} is not executable."
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SERVER} is not an ELF compiled executable."

    # Ensure server.c is genuinely compilable as a C program.
    rebuilt = f"/tmp/server_from_source_{os.getpid()}"
    result = subprocess.run(
        ["gcc", "-std=gnu11", "-O2", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"server.c did not compile successfully:\n{result.stderr}"
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    # The listener left by the agent must actually be the demanded executable,
    # rather than an unrelated script or process occupying port 9000.
    initial_pids = listening_pids()
    assert initial_pids, f"No process is listening on {HOST}:{PORT}."
    assert any(same_file_as_server(pid) for pid in initial_pids), (
        f"The listener on port {PORT} is not {SERVER}."
    )

    stop_port()
    proc = subprocess.Popen(
        [SERVER],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    messages = make_messages()
    expected_log_lines = []
    window = []
    boundaries = [13, 41, 73, len(messages)]
    start = 0

    try:
        for end in boundaries:
            s = connect_when_ready()
            s.settimeout(3)
            with s, s.makefile("rb") as reader:
                for msg in messages[start:end]:
                    cp_count = len(msg)
                    window.append(cp_count)
                    if len(window) > N:
                        window.pop(0)
                    expected_sum = sum(window)
                    expected_log_lines.append(
                        f"RECV: {cp_count} | WINDOW_SUM: {expected_sum}\n"
                    )

                    s.sendall(msg.encode("utf-8") + b"\n")
                    response = reader.readline()
                    assert response == f"{expected_sum}\n".encode("ascii"), (
                        f"Expected {expected_sum!r} for message {msg!r}, "
                        f"got {response!r}"
                    )
            start = end

        assert os.path.isfile(LOG), f"Log file {LOG} does not exist."
        with open(LOG, "r", encoding="utf-8") as f:
            actual_log_lines = f.readlines()
        assert len(actual_log_lines) >= len(expected_log_lines), (
            "Log file has fewer lines than expected."
        )
        recent = actual_log_lines[-len(expected_log_lines):]
        assert recent == expected_log_lines, (
            "Log file contents do not match the expected format or rolling sums."
        )
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                proc.kill()
            except ProcessLookupError:
                pass
        stop_port()
        try:
            os.unlink(rebuilt)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
