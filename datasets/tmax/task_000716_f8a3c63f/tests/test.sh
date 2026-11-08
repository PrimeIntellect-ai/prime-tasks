#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import signal
import socket
import subprocess
import time

import pytest

LOGS_DIR = "/home/user/logs"
SERVER_SOURCE = "/home/user/log_server.c"
SERVER_BINARY = "/home/user/log_server"
HOST = "127.0.0.1"
PORT = 9090


def _listener_inodes():
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
                    if state != "0A":
                        continue
                    try:
                        port = int(local_address.rsplit(":", 1)[1], 16)
                    except ValueError:
                        continue
                    if port == PORT:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def _listener_pids():
    inodes = _listener_inodes()
    pids = set()
    if not inodes:
        return pids

    for proc_entry in glob.glob("/proc/[0-9]*"):
        pid_text = os.path.basename(proc_entry)
        try:
            fd_dir = os.path.join(proc_entry, "fd")
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(pid_text))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def _wait_for_listener(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = _listener_pids()
        if pids:
            return pids
        time.sleep(0.05)
    return set()


def _assert_listener_executable(expected_binary):
    pids = _listener_pids()
    assert pids, f"No process is listening on TCP port {PORT}."
    unexpected = []
    for pid in pids:
        try:
            if not os.path.samefile(f"/proc/{pid}/exe", expected_binary):
                unexpected.append((pid, os.readlink(f"/proc/{pid}/exe")))
        except OSError as e:
            unexpected.append((pid, str(e)))
    assert not unexpected, (
        f"The listener on port {PORT} is not running from {expected_binary}: "
        f"{unexpected}"
    )


def _stop_listeners():
    pids = _listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 2
    while time.time() < deadline and _listener_pids():
        time.sleep(0.05)

    for pid in _listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    deadline = time.time() + 2
    while time.time() < deadline and _listener_pids():
        time.sleep(0.05)
    assert not _listener_pids(), f"Could not clear the existing listener on port {PORT}."


def _expected_output(path):
    try:
        raw_output = subprocess.check_output(["/app/bin/zdecoder", path])
        return raw_output.decode("utf-16le").encode("utf-8")
    except Exception as e:
        pytest.fail(f"Failed to generate expected output using zdecoder: {e}")


def _query(path, timeout=12):
    try:
        s = socket.create_connection((HOST, PORT), timeout=5)
    except Exception as e:
        pytest.fail(f"Could not connect to server at {HOST}:{PORT}: {e}")

    try:
        s.settimeout(timeout)
        s.sendall(f"{path}\n".encode("utf-8"))
        chunks = []
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks)
    except Exception as e:
        pytest.fail(f"Error communicating with server: {e}")
    finally:
        s.close()


def _make_random_archive(tag):
    nonce = secrets.token_hex(24)
    text = "".join(
        f"{tag}-{i:05d}-{nonce}-Καλημέρα-日志-🙂\n"
        for i in range(3500)
    )
    raw = text.encode("utf-16le")
    encoded = bytearray(len(raw) * 2)
    encoded[0::2] = b"\x01" * len(raw)
    encoded[1::2] = bytes(value ^ 0xAA for value in raw)
    path = os.path.join(LOGS_DIR, f"verifier-{tag}-{secrets.token_hex(12)}.legacy.z")
    with open(path, "wb") as f:
        f.write(encoded)
    return path


def test_files_renamed():
    """Check that every original .zlog archive was renamed."""
    zlog_files = glob.glob(os.path.join(LOGS_DIR, "*.zlog"))
    assert len(zlog_files) == 0, f"Found .zlog files still remaining in {LOGS_DIR}."

    legacy_files = glob.glob(os.path.join(LOGS_DIR, "*.legacy.z"))
    assert len(legacy_files) > 0, f"No .legacy.z files found in {LOGS_DIR}."

    syslog_path = os.path.join(LOGS_DIR, "syslog.legacy.z")
    auth_path = os.path.join(LOGS_DIR, "auth.legacy.z")
    assert os.path.isfile(syslog_path), f"Expected file {syslog_path} does not exist."
    assert os.path.isfile(auth_path), f"Expected file {auth_path} does not exist."
    assert not os.path.exists(os.path.join(LOGS_DIR, "syslog.zlog"))
    assert not os.path.exists(os.path.join(LOGS_DIR, "auth.zlog"))


def test_c_program_exists():
    """Check that the C source and compiled binary exist."""
    assert os.path.isfile(SERVER_SOURCE), "Source file /home/user/log_server.c is missing."
    assert os.path.isfile(SERVER_BINARY), "Compiled binary /home/user/log_server is missing."
    assert os.access(SERVER_BINARY, os.X_OK), "Compiled binary /home/user/log_server is not executable."


def test_server_response_and_artifacts():
    """Exercise the running binary and a fresh build of the submitted C source."""
    syslog_path = os.path.join(LOGS_DIR, "syslog.legacy.z")
    auth_path = os.path.join(LOGS_DIR, "auth.legacy.z")
    assert os.path.exists(syslog_path), f"Cannot test server, {syslog_path} missing."
    assert os.path.exists(auth_path), f"Cannot test server, {auth_path} missing."

    # Establish that the listener left by the agent is the submitted executable.
    _assert_listener_executable(SERVER_BINARY)

    # Preserve the original syslog check and also ensure the auth archive was renamed,
    # retained, and can be decoded.
    assert _query(syslog_path) == _expected_output(syslog_path), (
        "Server response does not match the expected UTF-8 output."
    )
    assert _query(auth_path) == _expected_output(auth_path), (
        "Server response for auth.legacy.z does not match the expected UTF-8 output."
    )

    # Use an unpredictable path and payload large enough to require multiple I/O chunks.
    first_probe = _make_random_archive("binary")
    try:
        assert _query(first_probe) == _expected_output(first_probe), (
            "Submitted binary failed an arbitrary-path streaming conversion test."
        )
    finally:
        try:
            os.unlink(first_probe)
        except FileNotFoundError:
            pass

    # Compile the submitted source independently so a valid binary cannot be paired
    # with unrelated or nonfunctional source.
    fresh_binary = f"/tmp/log_server_from_source_{os.getpid()}"
    build = subprocess.run(
        ["gcc", "-O2", SERVER_SOURCE, "-o", fresh_binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert build.returncode == 0, f"Submitted C source did not compile:\n{build.stderr}"
    assert os.access(fresh_binary, os.X_OK)

    _stop_listeners()
    subprocess.Popen(
        [fresh_binary],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )
    assert _wait_for_listener(), "Freshly compiled source did not start a listener on port 9090."
    _assert_listener_executable(fresh_binary)

    second_probe = _make_random_archive("source")
    try:
        assert _query(second_probe) == _expected_output(second_probe), (
            "Freshly compiled C source failed an arbitrary-path streaming conversion test."
        )
        assert _query(syslog_path) == _expected_output(syslog_path)
    finally:
        try:
            os.unlink(second_probe)
        except FileNotFoundError:
            pass
    # Intentionally leave the source-built server running in the background.
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
