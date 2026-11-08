#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import re
import secrets
import struct
import subprocess
import time

import pytest

INCOMING_DIR = "/home/user/incoming_docs"
ARCHIVE_DIR = "/home/user/archive"
ARCHIVE_FILE = os.path.join(ARCHIVE_DIR, "docs.bin")
SOURCE_FILE = "/home/user/doc_watcher.c"
PROGRAM_FILE = "/home/user/doc_watcher"


def parse_archive(data):
    offset = 0
    records = []
    while offset < len(data):
        assert offset + 2 <= len(data), "Truncated record (magic bytes)."
        magic = data[offset:offset + 2]
        assert magic == b"\xca\xd0", f"Invalid magic bytes at offset {offset}: {magic.hex()}"
        offset += 2

        assert offset + 4 <= len(data), "Truncated record (title length)."
        title_len = struct.unpack("<I", data[offset:offset + 4])[0]
        offset += 4

        assert offset + title_len <= len(data), "Truncated record (title)."
        title = data[offset:offset + title_len]
        offset += title_len

        assert offset + 4 <= len(data), "Truncated record (content length)."
        content_len = struct.unpack("<I", data[offset:offset + 4])[0]
        offset += 4

        assert offset + content_len <= len(data), "Truncated record (content)."
        content = data[offset:offset + content_len]
        offset += content_len
        records.append({"title": title, "content": content})
    return records


def archive_bytes():
    with open(ARCHIVE_FILE, "rb") as f:
        return f.read()


def wait_for_record(path, expected_title, expected_content, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if not os.path.exists(path) and os.path.isfile(ARCHIVE_FILE):
                data = archive_bytes()
                assert len(data) > 0, "Archive file is empty."
                records = parse_archive(data)
                assert len(records) > 0, "No records found in archive."
                last = records[-1]
                assert last["title"] == expected_title.encode("utf-8")
                assert last["content"] == expected_content.encode("utf-8")
                return
        except AssertionError as exc:
            last_error = exc
        time.sleep(0.1)
    if os.path.exists(path):
        pytest.fail(f"Test file {path} was not deleted by the daemon.")
    if last_error:
        raise last_error
    pytest.fail("Daemon did not append the expected archive record.")


def exact_daemon_pids():
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            exe = os.readlink(f"/proc/{entry}/exe")
            if exe == PROGRAM_FILE:
                result.append(int(entry))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return result


def test_daemon_running_and_artifacts():
    # Retain the original process-name assertion.
    try:
        output = subprocess.check_output(["pgrep", "-f", "doc_watcher"]).decode("utf-8")
        assert output.strip(), "doc_watcher process is not running."
    except subprocess.CalledProcessError:
        pytest.fail("doc_watcher process is not running.")

    assert os.path.isfile(SOURCE_FILE), f"{SOURCE_FILE} does not exist."
    assert os.path.isfile(PROGRAM_FILE), f"{PROGRAM_FILE} does not exist."
    assert os.access(PROGRAM_FILE, os.X_OK), f"{PROGRAM_FILE} is not executable."
    with open(PROGRAM_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "doc_watcher is not a compiled ELF executable."

    pids = exact_daemon_pids()
    assert pids, "No running process is executing /home/user/doc_watcher."

    # A real inotify watcher retains an inotify descriptor while waiting.
    has_inotify_fd = False
    for pid in pids:
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == "anon_inode:inotify":
                        has_inotify_fd = True
                except OSError:
                    pass
        except OSError:
            pass
    assert has_inotify_fd, "Running daemon has no inotify descriptor."

    source = open(SOURCE_FILE, "r", encoding="utf-8", errors="replace").read()
    for api in ("inotify_init", "inotify_add_watch", "flock", "iconv_open", "iconv", "iconv_close"):
        assert re.search(r"\b" + re.escape(api) + r"\s*\(", source), f"Source does not call {api}()."
    assert "IN_CLOSE_WRITE" in source, "Source does not request IN_CLOSE_WRITE events."
    assert "IN_MOVED_TO" in source, "Source does not request IN_MOVED_TO events."


def test_daemon_processing_dynamic_inputs_and_locks():
    assert os.path.isdir(INCOMING_DIR), f"{INCOMING_DIR} does not exist."
    assert os.path.isdir(ARCHIVE_DIR), f"{ARCHIVE_DIR} does not exist."

    token = secrets.token_hex(8)

    # Exercise IN_CLOSE_WRITE with an answer generated only at verification time.
    title1 = f"Caf\u00e9-{token}-Ni\u00f1o"
    content1 = f"R\u00e9sum\u00e9 {secrets.token_hex(13)}\nDeuxi\u00e8me ligne \u00a3.\n"
    path1 = os.path.join(INCOMING_DIR, f"close_{token}.txt")
    with open(path1, "wb") as f:
        f.write((title1 + "\n" + content1).encode("iso-8859-1"))
    wait_for_record(path1, title1, content1)

    # Exercise IN_MOVED_TO using a second independent randomized record.
    title2 = f"M\u00fcnchen-{secrets.token_hex(7)}"
    content2 = f"Se\u00f1al movida: {secrets.token_hex(17)}.\n"
    path2 = os.path.join(INCOMING_DIR, f"moved_{token}.txt")
    staging = os.path.join("/home/user", f".staging_{token}.txt")
    with open(staging, "wb") as f:
        f.write((title2 + "\n" + content2).encode("iso-8859-1"))
    os.replace(staging, path2)
    wait_for_record(path2, title2, content2)

    # Hold an exclusive lock on the incoming file through a separate descriptor.
    # The daemon must not consume it until flock can be acquired.
    title3 = f"Verrouill\u00e9-{secrets.token_hex(6)}"
    content3 = f"Entr\u00e9e prot\u00e9g\u00e9e {secrets.token_hex(15)}.\n"
    path3 = os.path.join(INCOMING_DIR, f"input_lock_{token}.txt")
    lock_fd = os.open(path3, os.O_CREAT | os.O_RDWR, 0o666)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    before = archive_bytes()
    with open(path3, "wb") as f:
        f.write((title3 + "\n" + content3).encode("iso-8859-1"))
    time.sleep(1)
    assert os.path.exists(path3), "Daemon ignored the exclusive input-file lock."
    assert archive_bytes() == before, "Daemon archived an input while its exclusive lock was held."
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    os.close(lock_fd)
    wait_for_record(path3, title3, content3)

    # Hold docs.bin locked while another close-write event arrives. This verifies
    # that appending and deletion wait for the archive's exclusive flock.
    title4 = f"Archiv\u00e9-{secrets.token_hex(6)}"
    content4 = f"Contenu concurrent {secrets.token_hex(19)} \u00d6.\n"
    path4 = os.path.join(INCOMING_DIR, f"archive_lock_{token}.txt")
    archive_fd = os.open(ARCHIVE_FILE, os.O_RDWR)
    fcntl.flock(archive_fd, fcntl.LOCK_EX)
    before = archive_bytes()
    with open(path4, "wb") as f:
        f.write((title4 + "\n" + content4).encode("iso-8859-1"))
    time.sleep(1)
    assert archive_bytes() == before, "Daemon appended without respecting the docs.bin lock."
    assert os.path.exists(path4), "Daemon deleted the input before its locked archive append completed."
    fcntl.flock(archive_fd, fcntl.LOCK_UN)
    os.close(archive_fd)
    wait_for_record(path4, title4, content4)

    # Parse the complete archive, retaining the original structural assertions.
    data = archive_bytes()
    assert len(data) > 0, "Archive file is empty."
    records = parse_archive(data)
    assert len(records) > 0, "No records found in archive."
    assert records[-1]["title"] == title4.encode("utf-8")
    assert records[-1]["content"] == content4.encode("utf-8")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
