#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import signal
import socket
import subprocess
import time
import pytest

HOST = "127.0.0.1"
PORT = 7777
SERVER_PROC = None


def _listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        try:
                            port = int(fields[1].rsplit(":", 1)[1], 16)
                        except ValueError:
                            continue
                        if port == PORT:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def _clear_port():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = _listener_pids()
        if not pids:
            return
        for pid in pids:
            if pid != os.getpid():
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        time.sleep(0.2)


def _port_is_listening():
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 4 and fields[3] == "0A":
                        try:
                            if int(fields[1].rsplit(":", 1)[1], 16) == PORT:
                                return True
                        except ValueError:
                            pass
        except FileNotFoundError:
            pass
    return False


def _stop_server():
    global SERVER_PROC
    if SERVER_PROC is not None and SERVER_PROC.poll() is None:
        SERVER_PROC.terminate()
        try:
            SERVER_PROC.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            SERVER_PROC.kill()
            SERVER_PROC.wait(timeout=1.0)
    SERVER_PROC = None
    _clear_port()


def _start_server(path):
    global SERVER_PROC
    _stop_server()
    err = open("/tmp/verified_server.stderr", "ab", buffering=0)
    SERVER_PROC = subprocess.Popen(
        [path], stdout=subprocess.DEVNULL, stderr=err, start_new_session=True
    )
    deadline = time.time() + 5.0
    while time.time() < deadline:
        if SERVER_PROC.poll() is not None:
            pytest.fail(f"Server {path} exited before listening (code {SERVER_PROC.returncode})")
        if _port_is_listening():
            return
        time.sleep(0.05)
    pytest.fail(f"Server {path} did not listen on 127.0.0.1:{PORT}")


def _readline(stream):
    raw = stream.readline()
    assert raw, "Server closed the connection before returning a required bucket response"
    try:
        return raw.decode("ascii")
    except UnicodeDecodeError as exc:
        pytest.fail(f"Server returned non-ASCII data: {exc}")


def _wait_for_new_log(offset, expected_lines):
    deadline = time.time() + 3.0
    text = ""
    while time.time() < deadline:
        try:
            with open("/home/user/pipeline.log", "r") as f:
                f.seek(offset)
                text = f.read()
        except FileNotFoundError:
            text = ""
        if len(text.splitlines()) >= len(expected_lines):
            break
        time.sleep(0.05)
    actual = text.splitlines()
    assert actual == expected_lines, f"Unexpected newly appended log entries. Expected {expected_lines!r}, got {actual!r}"


def _generated_session():
    rng = secrets.SystemRandom()
    count = rng.randint(8, 13)
    averages = [float(rng.randint(-8, 25)) for _ in range(3)]
    for i in range(3, count):
        threshold = sum(averages[i-3:i]) / 2.0 + 2.5
        if rng.choice((True, False)):
            current = threshold + rng.choice((0.5, 1.0, 3.0, 6.0))
        else:
            current = threshold - rng.choice((0.0, 0.5, 2.0, 5.0))
        averages.append(current)

    base = rng.randrange(20000, 200000) * 10
    starts = []
    current_start = base
    for _ in range(count):
        starts.append(current_start)
        current_start += rng.randint(1, 4) * 10

    statuses = []
    for i, current in enumerate(averages):
        if i < 3:
            statuses.append("NORMAL")
        else:
            hist_avg = sum(averages[i-3:i]) / 3.0
            statuses.append("ANOMALY" if current > hist_avg * 1.5 + 2.5 else "NORMAL")

    expected_responses = [
        f"BUCKET {start} {avg:.2f} {status}\n"
        for start, avg, status in zip(starts, averages, statuses)
    ]
    expected_logs = [
        f"[INFO] Processed bucket {start}, avg: {avg:.2f}, status: {status}"
        for start, avg, status in zip(starts, averages, statuses)
    ]

    try:
        log_offset = os.path.getsize("/home/user/pipeline.log")
    except FileNotFoundError:
        log_offset = 0

    s = socket.create_connection((HOST, PORT), timeout=5.0)
    s.settimeout(5.0)
    stream = s.makefile("rb")
    try:
        for i, (start, avg) in enumerate(zip(starts, averages)):
            first = f"{start + 1},{avg - 1.25:.2f}\n".encode("ascii")
            split = rng.randint(1, len(first) - 1)
            s.sendall(first[:split])
            time.sleep(0.003)
            s.sendall(first[split:])
            if i > 0:
                assert _readline(stream) == expected_responses[i-1]

            second = f"{start + 8},{avg + 1.25:.2f}\n".encode("ascii")
            s.sendall(second)

        s.shutdown(socket.SHUT_WR)
        assert _readline(stream) == expected_responses[-1]
        assert stream.readline() == b"", "Server emitted extra output after finalizing the last bucket"
    finally:
        stream.close()
        s.close()

    _wait_for_new_log(log_offset, expected_logs)


def test_server_files_exist():
    assert os.path.exists("/home/user/server.c"), "Source code /home/user/server.c is missing."
    assert os.path.exists("/home/user/server"), "Compiled binary /home/user/server is missing."
    assert os.access("/home/user/server", os.X_OK), "Compiled binary is not executable."
    with open("/home/user/server", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/server is not an ELF executable"


def test_tcp_server_logic_and_logging():
    _start_server("/home/user/server")
    host = '127.0.0.1'
    port = 7777

    try:
        with open("/home/user/pipeline.log", "r") as f:
            initial_log = f.read()
    except FileNotFoundError:
        initial_log = ""

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect((host, port))
    except Exception as e:
        pytest.fail(f"Could not connect to server at {host}:{port}: {e}")

    def send_and_expect(data_to_send, expected_response):
        s.sendall(data_to_send.encode('ascii'))
        if expected_response is not None:
            resp = s.recv(1024).decode('ascii')
            assert expected_response in resp, f"Expected '{expected_response}' in response, got '{resp}'"

    try:
        send_and_expect("100,10.0\n", None)
        send_and_expect("110,10.0\n", "BUCKET 100 10.00 NORMAL\n")
        send_and_expect("120,10.0\n", "BUCKET 110 10.00 NORMAL\n")
        send_and_expect("130,18.0\n", "BUCKET 120 10.00 NORMAL\n")
        send_and_expect("140,5.0\n", "BUCKET 130 18.00 ANOMALY\n")
    finally:
        s.close()

    time.sleep(0.5)
    assert os.path.exists("/home/user/pipeline.log"), "Log file /home/user/pipeline.log does not exist."
    with open("/home/user/pipeline.log", "r") as f:
        final_log = f.read()

    expected_logs = [
        "[INFO] Processed bucket 100, avg: 10.00, status: NORMAL",
        "[INFO] Processed bucket 110, avg: 10.00, status: NORMAL",
        "[INFO] Processed bucket 120, avg: 10.00, status: NORMAL",
        "[INFO] Processed bucket 130, avg: 18.00, status: ANOMALY",
        "[INFO] Processed bucket 140, avg: 5.00, status: NORMAL"
    ]
    for log_line in expected_logs:
        assert log_line in final_log, f"Expected log line '{log_line}' not found in /home/user/pipeline.log"


def test_randomized_streaming_behavior_of_submitted_binary():
    assert SERVER_PROC is not None and SERVER_PROC.poll() is None
    for _ in range(3):
        _generated_session()


def test_rebuilt_source_has_same_general_behavior():
    rebuilt = "/tmp/server_rebuilt_from_submission"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/server.c", "-o", rebuilt, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, f"/home/user/server.c did not compile:\n{result.stderr}"
    _start_server(rebuilt)
    for _ in range(2):
        _generated_session()
    _start_server("/home/user/server")
    assert SERVER_PROC.poll() is None
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
