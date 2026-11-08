#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import ctypes
import hashlib
import json
import os
import secrets
import select
import shutil
import struct
import subprocess
import time
import pytest


def test_repo_files_exist_and_content():
    repo_dir = "/home/user/repo"

    file1 = os.path.join(repo_dir, "CORE_b10a8db164e0754105b7a99be72e3fe5.bin")
    file2 = os.path.join(repo_dir, "CORE_70db6bfbe5a8c2ba42718cd99818817a.bin")

    assert os.path.isfile(file1), f"Expected file {file1} does not exist. The payload was not extracted or the filename is incorrect."
    assert os.path.isfile(file2), f"Expected file {file2} does not exist. The payload was not extracted or the filename is incorrect."

    with open(file1, "rb") as f:
        content1 = f.read()
    assert content1 == b"Hello World", f"Content of {file1} is incorrect. Expected 'Hello World', got {content1}"

    with open(file2, "rb") as f:
        content2 = f.read()
    assert content2 == b"Valid Payload 2", f"Content of {file2} is incorrect. Expected 'Valid Payload 2', got {content2}"


def test_no_extra_bin_files():
    repo_dir = "/home/user/repo"
    if not os.path.exists(repo_dir):
        pytest.fail(f"Directory {repo_dir} does not exist.")

    bin_files = [f for f in os.listdir(repo_dir) if f.endswith(".bin")]

    assert len(bin_files) == 2, f"Expected exactly 2 .bin files in {repo_dir}, but found {len(bin_files)}: {bin_files}"


def test_summary_file():
    summary_path = "/home/user/summary.txt"
    assert os.path.isfile(summary_path), f"Summary file {summary_path} does not exist."

    with open(summary_path, "r") as f:
        content = f.read().strip()

    assert content == "2", f"Summary file content is incorrect. Expected '2', got '{content}'"


def wal_entry(level, prefix, payload, end=True):
    encoded = base64.b64encode(payload).decode("ascii")
    text = f"[START]\nLEVEL: {level}\nPREFIX: {prefix}\nPAYLOAD: {encoded}\n"
    if end:
        text += "[END]\n"
    return text


def test_program_on_runtime_generated_inputs_and_atomic_writes():
    source = "/home/user/curator.go"
    assert os.path.isfile(source), "Required Go source /home/user/curator.go does not exist"
    assert not os.path.islink(source), "curator.go must be a real source file"

    binary = "/tmp/curator-under-test"
    build = subprocess.run(
        ["go", "build", "-o", binary, source],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"curator.go did not compile:\n{build.stdout}\n{build.stderr}"

    staging = "/home/user/staging"
    repo = "/home/user/repo"
    shutil.rmtree(staging, ignore_errors=True)
    shutil.rmtree(repo, ignore_errors=True)
    os.makedirs(staging)
    os.makedirs(repo)
    try:
        os.unlink("/home/user/summary.txt")
    except FileNotFoundError:
        pass

    prefix = "P" + secrets.token_hex(7)
    wrong_prefix = prefix + "_OTHER"
    min_level = secrets.randbelow(20) + 20
    with open("/home/user/config.json", "w") as f:
        json.dump({"min_level": min_level, "allowed_prefix": prefix}, f)

    payload1 = os.urandom(32768)
    payload2 = ("runtime-payload-" + secrets.token_hex(24)).encode()
    low_payload = os.urandom(41)
    wrong_payload = os.urandom(43)
    incomplete_payload = os.urandom(47)

    # This file includes accepted records, both filter failures, and an
    # incomplete record immediately followed by a new START marker.
    file_a = (
        wal_entry(min_level, prefix, payload1)
        + wal_entry(min_level - 1, prefix, low_payload)
        + wal_entry(min_level + 5, wrong_prefix, wrong_payload)
        + wal_entry(min_level + 9, prefix, incomplete_payload, end=False)
        + wal_entry(min_level + 1, prefix, payload2)
    )
    with open(os.path.join(staging, "generated-a.wal"), "w") as f:
        f.write(file_a)

    # Invalid base64 and an entry incomplete at EOF must not produce files.
    with open(os.path.join(staging, "generated-b.wal"), "w") as f:
        f.write(
            f"[START]\nLEVEL: {min_level + 2}\nPREFIX: {prefix}\nPAYLOAD: !!!!not-base64!!!!\n[END]\n"
        )
        f.write(wal_entry(min_level + 3, prefix, os.urandom(53), end=False))

    # A correctly formatted record outside a .wal file must be ignored.
    with open(os.path.join(staging, "ignored.txt"), "w") as f:
        f.write(wal_entry(min_level + 10, prefix, os.urandom(59)))

    expected = {
        f"{prefix}_{hashlib.md5(payload1).hexdigest()}.bin": payload1,
        f"{prefix}_{hashlib.md5(payload2).hexdigest()}.bin": payload2,
    }

    # Observe repository operations through inotify. A compliant same-directory
    # temporary-file-and-rename write delivers MOVED_TO for each final filename;
    # directly opening a final .bin only delivers CREATE.
    libc = ctypes.CDLL(None, use_errno=True)
    IN_NONBLOCK = 0x800
    IN_CREATE = 0x00000100
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    fd = libc.inotify_init1(IN_NONBLOCK)
    assert fd >= 0, f"inotify_init1 failed with errno {ctypes.get_errno()}"
    wd = libc.inotify_add_watch(fd, repo.encode(), IN_CREATE | IN_MOVED_FROM | IN_MOVED_TO)
    assert wd >= 0, f"inotify_add_watch failed with errno {ctypes.get_errno()}"

    events = []
    try:
        proc = subprocess.Popen([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        deadline = time.time() + 30
        while proc.poll() is None:
            assert time.time() < deadline, "curator program timed out"
            ready, _, _ = select.select([fd], [], [], 0.1)
            if ready:
                data = os.read(fd, 1024 * 1024)
                offset = 0
                while offset < len(data):
                    _, mask, _, name_len = struct.unpack_from("iIII", data, offset)
                    offset += 16
                    name = data[offset:offset + name_len].split(b"\0", 1)[0].decode(errors="replace")
                    offset += name_len
                    events.append((mask, name))
        stdout, stderr = proc.communicate(timeout=5)

        # Drain events queued between the last poll and process exit.
        while True:
            ready, _, _ = select.select([fd], [], [], 0)
            if not ready:
                break
            data = os.read(fd, 1024 * 1024)
            offset = 0
            while offset < len(data):
                _, mask, _, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                name = data[offset:offset + name_len].split(b"\0", 1)[0].decode(errors="replace")
                offset += name_len
                events.append((mask, name))
    finally:
        os.close(fd)

    assert proc.returncode == 0, f"curator execution failed ({proc.returncode}):\n{stdout}\n{stderr}"

    actual_bins = sorted(name for name in os.listdir(repo) if name.endswith(".bin"))
    assert actual_bins == sorted(expected), f"Incorrect generated .bin files: {actual_bins}"
    for name, payload in expected.items():
        path = os.path.join(repo, name)
        assert os.path.isfile(path), f"Expected output is not a regular file: {path}"
        with open(path, "rb") as f:
            assert f.read() == payload, f"Decoded content is incorrect for {name}"

    leftovers = [name for name in os.listdir(repo) if not name.endswith(".bin")]
    assert leftovers == [], f"Temporary files were left in the repository: {leftovers}"

    assert os.path.isfile("/home/user/summary.txt"), "Program did not create summary.txt"
    with open("/home/user/summary.txt") as f:
        assert f.read().strip() == str(len(expected)), "Dynamic-run summary count is incorrect"

    moved_to = {name for mask, name in events if mask & IN_MOVED_TO}
    assert set(expected).issubset(moved_to), (
        "Each final .bin must be installed by renaming a temporary file in the repository; "
        f"missing rename events for {sorted(set(expected) - moved_to)}"
    )
    temp_creates = [name for mask, name in events if (mask & IN_CREATE) and name not in expected]
    assert temp_creates, "No same-directory temporary file creation was observed"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
