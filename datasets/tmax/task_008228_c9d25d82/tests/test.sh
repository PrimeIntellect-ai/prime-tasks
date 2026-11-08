#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import hashlib
import os
import re
import secrets
import shutil
import signal
import subprocess
import tarfile
import time

import pytest

SOURCE = "/home/user/src/watcher.c"
EXECUTABLE = "/home/user/bin/watcher"
INCOMING = "/home/user/incoming"
BACKUP = "/home/user/backup"
LOG_FILE = os.path.join(BACKUP, "watcher.log")
TAR_FILE = os.path.join(BACKUP, "master.tar")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_log():
    if not os.path.isfile(LOG_FILE):
        return ""
    with open(LOG_FILE, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def wait_for_log_line(process, line, timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert process.poll() is None, "Watcher process exited prematurely."
        if line in read_log().splitlines():
            return
        time.sleep(0.05)
    pytest.fail(f"Timed out waiting for log line: {line}")


def write_closed(name, data):
    with open(os.path.join(INCOMING, name), "wb") as f:
        f.write(data)


def test_watcher_executable_exists_and_is_c_program():
    assert os.path.isfile(SOURCE), "Source file /home/user/src/watcher.c does not exist."
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."

    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "watcher is not a compiled ELF executable."

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"\binotify_(?:init|init1)\s*\(", source), "Source does not initialize inotify."
    assert re.search(r"\binotify_add_watch\s*\(", source), "Source does not add an inotify watch."
    assert "IN_CLOSE_WRITE" in source, "Source does not request IN_CLOSE_WRITE events."

    rebuilt = "/tmp/watcher_rebuilt"
    result = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt, "-lcrypto"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"watcher.c does not compile:\n{result.stderr}"


def test_watcher_behavior_with_unpredictable_stream():
    os.makedirs(INCOMING, exist_ok=True)
    os.makedirs(BACKUP, exist_ok=True)
    for entry in os.listdir(INCOMING):
        path = os.path.join(INCOMING, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    for path in (LOG_FILE, TAR_FILE):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    process = subprocess.Popen(
        [EXECUTABLE], cwd=INCOMING,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(0.8)
        assert process.poll() is None, "Watcher process exited prematurely."

        # Verify that the running artifact really holds an inotify descriptor.
        fd_dir = f"/proc/{process.pid}/fd"
        links = []
        for fd in os.listdir(fd_dir):
            try:
                links.append(os.readlink(os.path.join(fd_dir, fd)))
            except OSError:
                pass
        assert any("anon_inode:inotify" in link for link in links), \
            "Running watcher has no inotify descriptor."

        # Preserve the original fixed behavioral assertions.
        fixed_a = b"data set A\n"
        fixed_b = b"data set B\n"
        write_closed("test1.dat", fixed_a)
        wait_for_log_line(process, f"ADDED test1.dat {sha256(fixed_a)}")
        write_closed("test2.dat", fixed_b)
        wait_for_log_line(process, f"ADDED test2.dat {sha256(fixed_b)}")
        write_closed("test3.dat", fixed_a)
        wait_for_log_line(process, f"DUPLICATE test3.dat {sha256(fixed_a)}")
        write_closed("test4.txt", b"ignore me\n")
        time.sleep(0.4)
        assert "test4.txt" not in read_log(), "Log contains entry for ignored file test4.txt"

        # Add unpredictable names and contents, generated only after the watcher starts.
        token = secrets.token_hex(8)
        held_name = f"held_{token}.dat"
        held_data = secrets.token_bytes(113) + token.encode()
        held_path = os.path.join(INCOMING, held_name)
        held = open(held_path, "wb")
        held.write(held_data)
        held.flush()
        os.fsync(held.fileno())
        time.sleep(0.8)
        assert held_name not in read_log(), "A .dat file was processed before IN_CLOSE_WRITE."
        held.close()
        wait_for_log_line(process, f"ADDED {held_name} {sha256(held_data)}")

        unique1 = f"sample_{secrets.token_hex(7)}.dat"
        duplicate1 = f"repeat_{secrets.token_hex(7)}.dat"
        unique2 = f"later_{secrets.token_hex(7)}.dat"
        duplicate2 = f"copy_{secrets.token_hex(7)}.dat"
        ignored = f"ignored_{secrets.token_hex(7)}.txt"
        data1 = secrets.token_bytes(257)
        data2 = secrets.token_bytes(389)

        write_closed(unique1, data1)
        wait_for_log_line(process, f"ADDED {unique1} {sha256(data1)}")
        write_closed(duplicate1, data1)
        wait_for_log_line(process, f"DUPLICATE {duplicate1} {sha256(data1)}")
        write_closed(ignored, secrets.token_bytes(91))
        time.sleep(0.3)
        assert ignored not in read_log(), "A non-.dat file was logged."
        write_closed(unique2, data2)
        wait_for_log_line(process, f"ADDED {unique2} {sha256(data2)}")
        write_closed(duplicate2, data2)
        wait_for_log_line(process, f"DUPLICATE {duplicate2} {sha256(data2)}")

        process.send_signal(signal.SIGINT)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            pytest.fail("Watcher did not exit gracefully on SIGINT.")

        assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} was not created."
        log_lines = read_log().splitlines()
        required = {
            f"ADDED test1.dat {sha256(fixed_a)}",
            f"ADDED test2.dat {sha256(fixed_b)}",
            f"DUPLICATE test3.dat {sha256(fixed_a)}",
            f"ADDED {held_name} {sha256(held_data)}",
            f"ADDED {unique1} {sha256(data1)}",
            f"DUPLICATE {duplicate1} {sha256(data1)}",
            f"ADDED {unique2} {sha256(data2)}",
            f"DUPLICATE {duplicate2} {sha256(data2)}",
        }
        for line in required:
            assert line in log_lines, f"Log missing exact entry: {line}"
        assert "test4.txt" not in read_log()
        assert ignored not in read_log()

        assert os.path.isfile(TAR_FILE), f"Tar file {TAR_FILE} was not created."
        expected_data = {
            "test1.dat": fixed_a,
            "test2.dat": fixed_b,
            held_name: held_data,
            unique1: data1,
            unique2: data2,
        }
        forbidden = {"test3.dat", "test4.txt", duplicate1, duplicate2, ignored}
        try:
            with tarfile.open(TAR_FILE, "r") as tar:
                members = [m for m in tar.getmembers() if m.isfile()]
                basenames = [os.path.basename(m.name.rstrip("/")) for m in members]
                counts = collections.Counter(basenames)
                for name, expected in expected_data.items():
                    assert counts[name] == 1, f"Expected exactly one archived member named {name}."
                    member = next(m for m in members if os.path.basename(m.name.rstrip("/")) == name)
                    extracted = tar.extractfile(member)
                    assert extracted is not None and extracted.read() == expected, \
                        f"Archived contents are incorrect for {name}."
                for name in forbidden:
                    assert counts[name] == 0, f"Ignored or duplicate file {name} was archived."
        except tarfile.TarError as e:
            pytest.fail(f"Failed to read tar archive {TAR_FILE}: {e}")

        assert not os.path.exists(os.path.join(INCOMING, "test3.dat")), \
            "Duplicate file test3.dat was not deleted from incoming directory."
        assert not os.path.exists(os.path.join(INCOMING, duplicate1)), \
            "Random duplicate was not deleted from incoming directory."
        assert not os.path.exists(os.path.join(INCOMING, duplicate2)), \
            "Later random duplicate was not deleted from incoming directory."
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
