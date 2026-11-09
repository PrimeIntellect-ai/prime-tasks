#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import os
import pwd
import re
import secrets
import select
import shutil
import struct
import subprocess
import tempfile
import time

SCRIPT_PATH = "/home/user/organize.sh"
PROJECT_DUMP = "/home/user/project_dump"
ELF64_DIR = "/home/user/organized/elf64"
WAL_DIR = "/home/user/organized/wal"
INVENTORY_PATH = "/home/user/inventory.txt"

IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800


def get_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        h.update(f.read())
    return h.hexdigest()


def expected_files():
    elf64 = []
    wal = []
    for root, dirs, files in os.walk(PROJECT_DUMP):
        for filename in files:
            filepath = os.path.join(root, filename)
            with open(filepath, 'rb') as f:
                header = f.read(7)
            if header.startswith(b'\x7f\x45\x4c\x46\x02'):
                elf64.append(filepath)
            elif header.startswith(b'WAL_v3\x00'):
                wal.append(filepath)
    return elf64, wal


def add_randomized_fixture():
    token = secrets.token_hex(12)
    deep = os.path.join(PROJECT_DUMP, "fresh_" + token, "deep level", "more_" + token)
    other = os.path.join(PROJECT_DUMP, "fresh_" + token, "other")
    os.makedirs(deep, exist_ok=True)
    os.makedirs(other, exist_ok=True)

    fixtures = {
        os.path.join(deep, "no_extension_" + token): b'\x7fELF\x02' + secrets.token_bytes(47),
        os.path.join(other, "misnamed.txt"): b'WAL_v3\x00' + secrets.token_bytes(53),
        os.path.join(deep, "second elf with spaces.dat"): b'\x7fELF\x02' + secrets.token_bytes(61),
        os.path.join(other, "elf32_" + token): b'\x7fELF\x01' + secrets.token_bytes(31),
        os.path.join(other, "bad_wal_" + token): b'WAL_v3X' + secrets.token_bytes(29),
        os.path.join(deep, "prefixed_" + token): b'X\x7fELF\x02' + secrets.token_bytes(27),
        os.path.join(deep, "short_" + token): b'WAL_v3',
    }
    for path, data in fixtures.items():
        with open(path, 'wb') as f:
            f.write(data)
        os.chmod(path, 0o644)
    for root, dirs, files in os.walk(os.path.join(PROJECT_DUMP, "fresh_" + token)):
        os.chmod(root, 0o755)


def reset_destinations():
    for path in (ELF64_DIR, WAL_DIR):
        shutil.rmtree(path, ignore_errors=True)
        os.makedirs(path, mode=0o777)
        os.chmod(path, 0o777)
    try:
        os.unlink(INVENTORY_PATH)
    except FileNotFoundError:
        pass


def run_and_observe_script():
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    fd = libc.inotify_init1(os.O_NONBLOCK)
    assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
    mask = IN_MOVED_TO | IN_CREATE | IN_DELETE_SELF | IN_MOVE_SELF
    wd_elf = libc.inotify_add_watch(fd, os.fsencode(ELF64_DIR), mask)
    wd_wal = libc.inotify_add_watch(fd, os.fsencode(WAL_DIR), mask)
    assert wd_elf >= 0 and wd_wal >= 0, "Could not monitor destination directories."

    user = pwd.getpwnam("user")
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    events = []

    def demote():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    with tempfile.TemporaryFile() as output:
        proc = subprocess.Popen(
            ["/bin/bash", SCRIPT_PATH],
            stdout=output,
            stderr=subprocess.STDOUT,
            env=env,
            preexec_fn=demote,
        )
        deadline = time.time() + 30
        while proc.poll() is None:
            assert time.time() < deadline, "Submitted script timed out."
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                events.extend(read_inotify_events(fd))
        while True:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if not ready:
                break
            events.extend(read_inotify_events(fd))
        output.seek(0)
        text = output.read().decode('utf-8', 'replace')
        assert proc.returncode == 0, f"Submitted script exited with {proc.returncode}:\n{text}"

    os.close(fd)
    return events, wd_elf, wd_wal


def read_inotify_events(fd):
    result = []
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        offset = 0
        while offset < len(data):
            wd, mask, cookie, name_len = struct.unpack_from('iIII', data, offset)
            offset += 16
            raw_name = data[offset:offset + name_len].split(b'\x00', 1)[0]
            offset += name_len
            result.append((wd, mask, os.fsdecode(raw_name)))
    return result


def test_execute_script_on_fresh_randomized_inputs_and_use_atomic_renames():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} not found."
    add_randomized_fixture()
    reset_destinations()

    expected_elf64, expected_wal = expected_files()
    assert len(expected_elf64) > 0, "No ELF64 files found in source."
    assert len(expected_wal) > 0, "No WAL files found in source."

    expected_atomic = []
    for path in expected_elf64:
        expected_atomic.append(("elf64", get_sha256(path)))
    for path in expected_wal:
        expected_atomic.append(("wal", get_sha256(path)))

    events, wd_elf, wd_wal = run_and_observe_script()
    moved_to = {
        ("elf64" if wd == wd_elf else "wal", name)
        for wd, mask, name in events
        if (mask & IN_MOVED_TO) and wd in (wd_elf, wd_wal)
    }
    direct_creates = {
        ("elf64" if wd == wd_elf else "wal", name)
        for wd, mask, name in events
        if (mask & IN_CREATE) and wd in (wd_elf, wd_wal)
    }

    for category, digest in expected_atomic:
        assert (category, digest) in moved_to, (
            f"Final {category} file {digest} was not atomically created by renaming "
            "a temporary file in its destination directory."
        )
        assert (category, digest) not in direct_creates, (
            f"Final {category} file {digest} was created directly instead of via rename."
        )


def test_script_exists_and_uses_mv():
    script_path = "/home/user/organize.sh"
    assert os.path.isfile(script_path), f"Script {script_path} not found."
    with open(script_path, 'r') as f:
        content = f.read()
    # Preserve the original assertion in addition to the behavioral atomicity check.
    assert re.search(r'\bmv\b', content), "Script does not appear to use 'mv' for atomic writes."


def test_organized_files_and_inventory():
    project_dump = "/home/user/project_dump"
    elf64_dir = "/home/user/organized/elf64"
    wal_dir = "/home/user/organized/wal"
    inventory_path = "/home/user/inventory.txt"

    assert os.path.isfile(inventory_path), f"Inventory file {inventory_path} not found."

    expected_elf64 = []
    expected_wal = []

    # Traverse project_dump to find expected files
    for root, dirs, files in os.walk(project_dump):
        for file in files:
            filepath = os.path.join(root, file)
            with open(filepath, 'rb') as f:
                header = f.read(7)

            if header.startswith(b'\x7f\x45\x4c\x46\x02'):
                expected_elf64.append(filepath)
            elif header.startswith(b'WAL_v3\x00'):
                expected_wal.append(filepath)

    assert len(expected_elf64) > 0, "No ELF64 files found in source."
    assert len(expected_wal) > 0, "No WAL files found in source."

    expected_mappings = {}

    for filepath in expected_elf64:
        h = get_sha256(filepath)
        dest = os.path.join(elf64_dir, h)
        expected_mappings[filepath] = dest
        assert os.path.isfile(dest), f"Expected ELF64 file {dest} not found."
        assert get_sha256(dest) == h, f"Content mismatch for {dest}."

    for filepath in expected_wal:
        h = get_sha256(filepath)
        dest = os.path.join(wal_dir, h)
        expected_mappings[filepath] = dest
        assert os.path.isfile(dest), f"Expected WAL file {dest} not found."
        assert get_sha256(dest) == h, f"Content mismatch for {dest}."

    # Check inventory
    with open(inventory_path, 'r') as f:
        inventory_lines = [line.strip() for line in f if line.strip()]

    assert len(inventory_lines) == len(expected_mappings), "Inventory line count mismatch."
    assert len(inventory_lines) == len(set(inventory_lines)), "Duplicate inventory entries found."

    actual_mappings = {}
    for line in inventory_lines:
        parts = line.split(" -> ")
        assert len(parts) == 2, f"Invalid inventory line format: {line}"
        src, dest = parts
        assert src in expected_mappings, f"Unexpected source file in inventory: {src}"
        assert expected_mappings[src] == dest, f"Incorrect destination in inventory for {src}: expected {expected_mappings[src]}, got {dest}"
        assert src not in actual_mappings, f"Source appears more than once in inventory: {src}"
        actual_mappings[src] = dest

    assert actual_mappings == expected_mappings, "Inventory does not contain every expected mapping exactly once."

    # Check for unexpected files in target dirs
    elf64_files = os.listdir(elf64_dir)
    assert len(elf64_files) == len(expected_elf64), "Unexpected files found in elf64 directory."

    wal_files = os.listdir(wal_dir)
    assert len(wal_files) == len(expected_wal), "Unexpected files found in wal directory."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
