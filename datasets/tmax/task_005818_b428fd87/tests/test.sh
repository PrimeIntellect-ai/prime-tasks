#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import struct
import subprocess
import shutil
import tempfile
import uuid
import time
import re
import fcntl
import pytest

CONFIGS_DIR = "/home/user/configs"
WAL_FILE = "/home/user/tracker.wal"
SYMLINK_FILE = "/home/user/latest.elf"
SOURCE_FILE = "/home/user/config_tracker.cpp"
PROGRAM_FILE = "/home/user/config_tracker"

def get_elf64_entry_point(filepath):
    """Extracts the e_entry field from an ELF64 binary."""
    with open(filepath, "rb") as f:
        e_ident = f.read(16)
        assert e_ident[:4] == b"\x7fELF", f"File {filepath} is not a valid ELF."
        assert e_ident[4] == 2, f"File {filepath} is not a 64-bit ELF."
        f.read(8)
        e_entry_bytes = f.read(8)
        endian = "<" if e_ident[5] == 1 else ">"
        return struct.unpack(f"{endian}Q", e_entry_bytes)[0]

def get_expected_updates():
    """Parses JSON metadata and sorts by timestamp."""
    updates = []
    for filename in os.listdir(CONFIGS_DIR):
        if filename.endswith(".json"):
            filepath = os.path.join(CONFIGS_DIR, filename)
            with open(filepath, "r") as f:
                updates.append(json.load(f))
    updates.sort(key=lambda x: x["timestamp"])
    return updates

def test_wal_file_exists_and_correct():
    assert os.path.exists(WAL_FILE), f"WAL file {WAL_FILE} does not exist."
    assert os.path.isfile(WAL_FILE), f"{WAL_FILE} is not a regular file."

    updates = get_expected_updates()
    assert len(updates) > 0, "No JSON updates found to verify against."

    expected_lines = []
    for update in updates:
        config_id = update["config_id"]
        binary = update["binary"]
        binary_path = os.path.join(CONFIGS_DIR, binary)
        entry_point = get_elf64_entry_point(binary_path)
        expected_lines.append(f"{config_id},{binary},{hex(entry_point)}")

    with open(WAL_FILE, "r") as f:
        actual_content = f.read().strip()
    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in WAL file, found {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"WAL line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"

def test_symlink_correct():
    assert os.path.islink(SYMLINK_FILE), f"{SYMLINK_FILE} does not exist or is not a symlink."

    updates = get_expected_updates()
    assert len(updates) > 0, "No JSON updates found to determine symlink target."
    expected_target = os.path.join(CONFIGS_DIR, updates[-1]["binary"])
    actual_target = os.readlink(SYMLINK_FILE)
    assert actual_target == expected_target, f"Symlink {SYMLINK_FILE} points to {actual_target}, expected {expected_target}."

def strip_comments_and_literals(source):
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    source = re.sub(r"//[^\n]*", " ", source)
    source = re.sub(r'R\"[^\n]*?\(.*?\)[^\n]*?\"', '""', source, flags=re.S)
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    source = re.sub(r"'(?:\\.|[^'\\])*'", "''", source)
    return source

def write_challenge_configs(base_configs, nonce):
    os.makedirs(CONFIGS_DIR, exist_ok=True)
    source_elf = os.path.join(base_configs, "app_v3.elf")
    order = [2, 0, 1]
    records = []

    for i in range(3):
        binary = f"probe_{nonce}_{i}.elf"
        destination = os.path.join(CONFIGS_DIR, binary)
        shutil.copyfile(source_elf, destination)
        os.chmod(destination, 0o755)

        with open(destination, "r+b") as f:
            ident = f.read(16)
            assert ident[:4] == b"\x7fELF" and ident[4] == 2
            endian = "<" if ident[5] == 1 else ">"
            entry = 0x120000 + i * 0x101 + int(nonce[:3], 16)
            f.seek(24)
            f.write(struct.pack(endian + "Q", entry))

        records.append({
            "config_id": f"cfg_{nonce}_{i}",
            "binary": binary,
            "timestamp": 1700000000 + order[i] * 17,
        })

    for i, record in enumerate(records):
        with open(os.path.join(CONFIGS_DIR, f"update_{nonce}_{i}.json"), "w") as f:
            json.dump(record, f, separators=(",", ":"))
            f.write("\n")

    return sorted(records, key=lambda item: item["timestamp"])

def exercise_program(executable, expected_updates):
    if os.path.lexists(SYMLINK_FILE):
        os.unlink(SYMLINK_FILE)
    if os.path.lexists(WAL_FILE):
        os.unlink(WAL_FILE)

    lock_fd = os.open(WAL_FILE, os.O_RDWR | os.O_CREAT | os.O_TRUNC, 0o666)
    os.chmod(WAL_FILE, 0o666)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    fcntl.lockf(lock_fd, fcntl.LOCK_EX)

    env = os.environ.copy()
    env["PATH"] = ""
    proc = subprocess.Popen(
        [executable, CONFIGS_DIR],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    try:
        time.sleep(0.5)
        assert proc.poll() is None, "Program completed while another process held an exclusive lock on tracker.wal."
        fcntl.lockf(lock_fd, fcntl.LOCK_UN)
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)
        lock_fd = None
        stdout, stderr = proc.communicate(timeout=10)
        assert proc.returncode == 0, f"Program failed on generated inputs. stdout={stdout!r}, stderr={stderr!r}"
    finally:
        if lock_fd is not None:
            try:
                fcntl.lockf(lock_fd, fcntl.LOCK_UN)
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
            finally:
                os.close(lock_fd)
        if proc.poll() is None:
            proc.kill()
            proc.communicate()

    expected_lines = []
    for update in expected_updates:
        path = os.path.join(CONFIGS_DIR, update["binary"])
        expected_lines.append(f"{update['config_id']},{update['binary']},{hex(get_elf64_entry_point(path))}")

    assert os.path.isfile(WAL_FILE), "Program did not create a regular WAL file."
    with open(WAL_FILE) as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, f"Generated-input WAL mismatch: {actual_lines!r} != {expected_lines!r}"

    assert os.path.islink(SYMLINK_FILE), "Program did not create latest.elf as a symbolic link."
    expected_target = os.path.join(CONFIGS_DIR, expected_updates[-1]["binary"])
    assert os.readlink(SYMLINK_FILE) == expected_target

def test_cpp_artifacts_and_implementation_behavior():
    assert os.path.isfile(SOURCE_FILE), f"Missing C++ source file {SOURCE_FILE}."
    assert os.path.isfile(PROGRAM_FILE), f"Missing compiled program {PROGRAM_FILE}."
    assert os.access(PROGRAM_FILE, os.X_OK), f"{PROGRAM_FILE} is not executable."
    with open(PROGRAM_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PROGRAM_FILE} is not an ELF executable."

    with open(SOURCE_FILE, "r", errors="replace") as f:
        source = f.read()
    code = strip_comments_and_literals(source)

    has_flock = re.search(r"\bflock\s*\(", code) is not None
    has_fcntl = re.search(r"\bfcntl\s*\(", code) is not None
    assert has_flock or has_fcntl, "C++ source does not call flock() or fcntl()."
    if has_flock:
        assert "LOCK_EX" in code, "flock() is present but no exclusive LOCK_EX operation is used."
    if has_fcntl:
        assert re.search(r"\bF_(?:OFD_)?SETLK(?:W)?\b", code), "fcntl() is present but no record-lock operation is used."

    forbidden_calls = ["system", "popen", "execl", "execle", "execlp", "execv", "execve", "execvp", "execvpe", "posix_spawn", "posix_spawnp"]
    for name in forbidden_calls:
        assert not re.search(rf"\b{name}\s*\(", code), f"C++ source shells out or launches another program via {name}()."

    rebuilt = os.path.join(tempfile.mkdtemp(prefix="tracker-build-"), "config_tracker")
    result = subprocess.run(
        ["g++", "-std=c++17", "-o", rebuilt, SOURCE_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"C++ source does not compile with C++17: {result.stderr}"

    backup_configs = f"/home/user/configs.verifier-backup-{uuid.uuid4().hex}"
    original_wal = open(WAL_FILE, "rb").read()
    original_link = os.readlink(SYMLINK_FILE)
    os.rename(CONFIGS_DIR, backup_configs)

    try:
        nonce1 = uuid.uuid4().hex[:10]
        expected1 = write_challenge_configs(backup_configs, nonce1)
        exercise_program(PROGRAM_FILE, expected1)

        shutil.rmtree(CONFIGS_DIR)
        nonce2 = uuid.uuid4().hex[:10]
        expected2 = write_challenge_configs(backup_configs, nonce2)
        exercise_program(rebuilt, expected2)
    finally:
        if os.path.isdir(CONFIGS_DIR):
            shutil.rmtree(CONFIGS_DIR)
        os.rename(backup_configs, CONFIGS_DIR)
        if os.path.lexists(WAL_FILE):
            os.unlink(WAL_FILE)
        with open(WAL_FILE, "wb") as f:
            f.write(original_wal)
        if os.path.lexists(SYMLINK_FILE):
            os.unlink(SYMLINK_FILE)
        os.symlink(original_link, SYMLINK_FILE)
        shutil.rmtree(os.path.dirname(rebuilt), ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
