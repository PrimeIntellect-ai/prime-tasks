#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import shutil
import signal
import subprocess
import time
from pathlib import Path

import pytest

ORACLE_PATH = "/app/manifest_hash_oracle"
AGENT_PATH = "/home/user/manifest_tool"
WATCHER_PATH = "/home/user/watch_project.sh"
PROJECT_PATH = Path("/home/user/project")
MANIFEST_PATH = Path("/home/user/manifest.txt")


def test_manifest_tool_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent tool missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent tool at {AGENT_PATH} is not executable"


def test_watcher_script_exists():
    assert os.path.exists(WATCHER_PATH), f"Watcher script missing at {WATCHER_PATH}"
    assert os.access(WATCHER_PATH, os.X_OK), f"Watcher script at {WATCHER_PATH} is not executable"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent tool missing at {AGENT_PATH}"

    random.seed(42)

    for i in range(1000):
        length = random.randint(0, 4096)
        # Generate random bytes (0x00 to 0xFF)
        test_data = bytearray(random.getrandbits(8) for _ in range(length))

        oracle_proc = subprocess.run([ORACLE_PATH], input=test_data, capture_output=True)
        agent_proc = subprocess.run([AGENT_PATH], input=test_data, capture_output=True)

        oracle_out = oracle_proc.stdout.decode('utf-8', errors='replace').strip()
        agent_out = agent_proc.stdout.decode('utf-8', errors='replace').strip()

        assert oracle_proc.returncode == 0, f"Oracle failed on input length {length}"
        assert agent_proc.returncode == 0, f"Agent tool failed on input length {length}"

        assert oracle_out == agent_out, (
            f"Mismatch on iteration {i} with input length {length}.\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output: {agent_out}"
        )


def oracle_hash(data):
    proc = subprocess.run([ORACLE_PATH], input=data, capture_output=True, timeout=5)
    assert proc.returncode == 0
    return proc.stdout.decode("ascii").strip()


def read_manifest():
    raw = MANIFEST_PATH.read_text(encoding="utf-8")
    lines = raw.splitlines()
    assert all(line for line in lines), "Manifest contains a blank or partial line"

    result = {}
    for line in lines:
        parts = line.rsplit(" ", 1)
        assert len(parts) == 2, f"Malformed manifest line: {line!r}"
        name, digest = parts
        assert name not in result, f"Duplicate manifest entry for {name!r}"
        assert len(digest) == 8
        int(digest, 16)
        result[name] = digest.lower()
    return result


def wait_for_manifest(expected, timeout=12):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            actual = read_manifest()
            if actual == expected:
                return os.lstat(MANIFEST_PATH).st_ino
        except (FileNotFoundError, UnicodeDecodeError, AssertionError, ValueError) as exc:
            last_error = exc
        time.sleep(0.05)
    try:
        actual = read_manifest()
    except Exception as exc:
        actual = f"unreadable: {exc}"
    pytest.fail(
        f"Manifest did not reach expected state. Expected {expected!r}, "
        f"last state {actual!r}, last transient error {last_error!r}"
    )


def test_watcher_updates_manifest_with_tool_and_atomic_replacement():
    # Start from an empty project while retaining a nested directory to verify
    # relative paths and recursive watching.
    PROJECT_PATH.mkdir(parents=True, exist_ok=True)
    for child in list(PROJECT_PATH.iterdir()):
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink()
    nested = PROJECT_PATH / "subdir"
    nested.mkdir()
    try:
        MANIFEST_PATH.unlink()
    except FileNotFoundError:
        pass

    # Interpose a transparent recorder at the required tool path. This verifies
    # that watcher updates actually invoke the submitted manifest_tool rather
    # than independently calculating or hard-coding hashes.
    backup = Path(f"/home/user/.manifest_tool.verifier.{os.getpid()}")
    call_log = Path(f"/tmp/manifest_tool_calls.{os.getpid()}")
    if backup.exists():
        backup.unlink()
    if call_log.exists():
        call_log.unlink()
    os.rename(AGENT_PATH, backup)
    wrapper = f'''#!/usr/bin/python3
import subprocess
import sys

data = sys.stdin.buffer.read()
with open({str(call_log)!r}, "ab") as log:
    log.write(b"call\\n")
proc = subprocess.run([{str(backup)!r}], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
sys.stdout.buffer.write(proc.stdout)
sys.stderr.buffer.write(proc.stderr)
raise SystemExit(proc.returncode)
'''
    Path(AGENT_PATH).write_text(wrapper, encoding="utf-8")
    os.chmod(AGENT_PATH, 0o755)

    watcher = None
    try:
        watcher = subprocess.Popen(
            [WATCHER_PATH],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        time.sleep(0.75)
        assert watcher.poll() is None, "Watcher exited instead of continuously watching"

        alpha_data_1 = b"first version\x00with binary\xffdata\n"
        alpha = PROJECT_PATH / "alpha.bin"
        alpha.write_bytes(alpha_data_1)
        expected = {"alpha.bin": oracle_hash(alpha_data_1)}
        inode1 = wait_for_manifest(expected)

        alpha_data_2 = b"second version of alpha\x00\x01\x02"
        alpha.write_bytes(alpha_data_2)
        expected = {"alpha.bin": oracle_hash(alpha_data_2)}
        inode2 = wait_for_manifest(expected)
        assert inode2 != inode1, (
            "Manifest inode did not change during an update; updates must use "
            "atomic replacement rather than modifying manifest.txt in place"
        )

        nested_data = bytes(range(256)) * 3
        nested_file = nested / "payload.dat"
        nested_file.write_bytes(nested_data)
        expected["subdir/payload.dat"] = oracle_hash(nested_data)
        inode3 = wait_for_manifest(expected)
        assert inode3 != inode2, (
            "Manifest inode did not change during an update; updates must use "
            "atomic replacement rather than modifying manifest.txt in place"
        )

        assert watcher.poll() is None, "Watcher stopped after processing file events"
        calls = call_log.read_bytes().splitlines() if call_log.exists() else []
        assert len(calls) >= 3, (
            "Watcher did not invoke /home/user/manifest_tool for each tested change"
        )
    finally:
        if watcher is not None and watcher.poll() is None:
            try:
                os.killpg(watcher.pid, signal.SIGTERM)
                watcher.wait(timeout=3)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(watcher.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        try:
            Path(AGENT_PATH).unlink()
        except FileNotFoundError:
            pass
        if backup.exists():
            os.rename(backup, AGENT_PATH)
        try:
            call_log.unlink()
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
