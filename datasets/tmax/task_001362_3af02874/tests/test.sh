#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import secrets
import shutil
import signal
import socket
import stat
import subprocess
import tarfile
import tempfile
import time

import pytest

HOST = "127.0.0.1"
PORT = 8888
SOURCE = "/home/user/backup_daemon.c"
DAEMON = "/home/user/backup_daemon"
RAW_LOGS = "/home/user/raw_logs"
BEGIN = b"+-- BEGIN RECORD --+"
END = b"+-- END RECORD --+"


def request_stats():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect((HOST, PORT))
            s.sendall(b"REQ: STATS\n")
            return s.recv(1024).decode("utf-8")
    except ConnectionRefusedError:
        pytest.fail("Connection refused on 127.0.0.1:8888. Is the server running?")
    except socket.timeout:
        pytest.fail("Socket timeout while waiting for STATS response.")


def request_download():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect((HOST, PORT))
            s.sendall(b"REQ: DOWNLOAD\n")
            data = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
            return data
    except ConnectionRefusedError:
        pytest.fail("Connection refused on 127.0.0.1:8888. Is the server running?")
    except socket.timeout:
        pytest.fail("Socket timeout while receiving DOWNLOAD response.")


def extract_clean_logs(data):
    assert len(data) > 0, "No data received for DOWNLOAD request"

    with tempfile.TemporaryDirectory() as tmpdir:
        tar_path = os.path.join(tmpdir, "backup.tar.gz")
        with open(tar_path, "wb") as f:
            f.write(data)

        try:
            with tarfile.open(tar_path, "r:gz") as tar:
                try:
                    member = tar.getmember("clean_logs.txt")
                except KeyError:
                    pytest.fail("clean_logs.txt not found at the root of the downloaded tarball")
                assert member.isfile(), "clean_logs.txt in the tarball is not a regular file"
                extracted = tar.extractfile(member)
                assert extracted is not None
                clean_data = extracted.read()
        except tarfile.TarError as e:
            pytest.fail(f"Downloaded data is not a valid gzip tarball: {e}")

        clean_logs_path = os.path.join(tmpdir, "clean_logs.txt")
        with open(clean_logs_path, "wb") as f:
            f.write(clean_data)
        assert os.path.exists(clean_logs_path), "clean_logs.txt not found at the root of the downloaded tarball"

        with open(clean_logs_path, "r") as f:
            lines = f.readlines()
        return clean_data, lines


def parse_log(path):
    records = []
    current = None
    with open(path, "rb") as f:
        for raw_line in f:
            line = raw_line[:-1] if raw_line.endswith(b"\n") else raw_line
            if line == BEGIN:
                current = []
            elif line == END:
                if current is not None:
                    records.append(b"".join(current))
                    current = None
            elif current is not None:
                current.append(raw_line)
    return records


def expected_records(root):
    records = []
    for directory, _, files in os.walk(root):
        for name in sorted(files):
            if name.endswith(".log"):
                records.extend(parse_log(os.path.join(directory, name)))
    return records


def listener_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for row in f:
                    fields = row.split()
                    if len(fields) > 9 and int(fields[1].split(":")[1], 16) == PORT and fields[3] == "0A":
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def listener_owners():
    inodes = listener_inodes()
    owners = set()
    if not inodes:
        return owners
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(entry))
                    break
        except OSError:
            continue
    return owners


def kill_port_listeners():
    for pid in listener_owners():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_inodes(), "Could not stop the old service on port 8888"


def wait_for_submitted_daemon():
    deadline = time.time() + 8
    while time.time() < deadline:
        for pid in listener_owners():
            try:
                if os.path.samefile(f"/proc/{pid}/exe", DAEMON):
                    return
            except (FileNotFoundError, PermissionError, OSError):
                pass
        time.sleep(0.05)
    pytest.fail("The executed /home/user/backup_daemon did not listen on 127.0.0.1:8888")


def test_complete_backup_daemon():
    assert os.path.isfile(SOURCE), "/home/user/backup_daemon.c is missing"
    assert os.path.getsize(SOURCE) > 0, "/home/user/backup_daemon.c is empty"
    assert os.path.isfile(DAEMON), "/home/user/backup_daemon is missing"
    mode = os.stat(DAEMON).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), "/home/user/backup_daemon is not executable"
    with open(DAEMON, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/backup_daemon is not an ELF executable"

    # Preserve the original service assertions, then verify its payload against
    # the records actually generated by the legacy logger.
    original_records = expected_records(RAW_LOGS)
    assert len(original_records) == 117, "The legacy logger output does not contain the expected 117 valid records"

    response = request_stats()
    assert response == "COUNT=117\n", f"Expected COUNT=117\\n, got {response!r}"

    original_data, original_lines = extract_clean_logs(request_download())
    assert len(original_lines) == 117, f"Expected 117 lines in clean_logs.txt, got {len(original_lines)}"
    for line in original_lines:
        assert line.startswith("DATA: "), f"Line in clean_logs.txt does not start with 'DATA: ': {line!r}"
    assert collections.Counter(original_data.splitlines(keepends=True)) == collections.Counter(original_records), \
        "Downloaded clean_logs.txt does not contain the payloads from the generated logs"

    # Replace the logs with unpredictable recursive test data and execute the
    # submitted artifact itself, preventing hard-coded counts or payloads.
    kill_port_listeners()
    shutil.rmtree(RAW_LOGS, ignore_errors=True)
    nested = os.path.join(RAW_LOGS, "hidden", "deeper")
    os.makedirs(nested, exist_ok=True)
    token = secrets.token_hex(20).encode("ascii")
    fixture = (
        b"noise outside records\n"
        + BEGIN + b"\n"
        + b"DATA: hidden-one-" + token + b"\n"
        + b"continuation-one-" + token + b"\n"
        + END + b"\n"
        + BEGIN + b"\n"
        + b"DATA: discarded-" + token + b"\n"
        + BEGIN + b"\n"
        + b"DATA: hidden-two-" + token + b"\n"
        + END + b"\n"
        + b"ordinary text\n"
        + BEGIN + b"\n"
        + b"DATA: hidden-three-" + token + b"\n"
        + END + b"\n"
        + BEGIN + b"\n"
        + b"DATA: truncated-" + token + b"\n"
    )
    with open(os.path.join(nested, "challenge.log"), "wb") as f:
        f.write(fixture)
    with open(os.path.join(RAW_LOGS, "ignored.txt"), "wb") as f:
        f.write(BEGIN + b"\nDATA: must-not-appear\n" + END + b"\n")

    hidden_records = expected_records(RAW_LOGS)
    assert len(hidden_records) == 3
    expected_clean = b"".join(hidden_records)

    proc = subprocess.Popen(
        [DAEMON], cwd="/home/user", stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        wait_for_submitted_daemon()
        response = request_stats()
        assert response == f"COUNT={len(hidden_records)}\n", \
            f"Expected dynamic count {len(hidden_records)}, got {response!r}"
        hidden_data, _ = extract_clean_logs(request_download())
        assert hidden_data == expected_clean, \
            "Downloaded clean_logs.txt does not exactly match the valid records in the recursive test logs"
    finally:
        kill_port_listeners()
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
