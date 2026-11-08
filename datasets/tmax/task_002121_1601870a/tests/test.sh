#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_secure_archiver.py
import collections
import os
import re
import shutil
import subprocess
import time
import uuid

import pytest

BINARY = "/home/user/secure_archiver"
SOURCE = "/home/user/secure_archiver.c"
SPOOL = "/home/user/spool"
STAGING = "/home/user/staging"
VAULT = "/home/user/vault"
LOG = "/home/user/security.log"


def wait_for(predicate, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    assert predicate(), "Timed out waiting for secure_archiver"


def test_compiled_binary():
    assert os.path.isfile(BINARY), f"Compiled binary missing at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable"


def test_vault_contents():
    expected_vault_files = [
        "/home/user/vault/reports/file1.txt",
        "/home/user/vault/images/file2.txt",
        "/home/user/vault/deep/nested/path/file3.txt"
    ]
    for path in expected_vault_files:
        assert os.path.isfile(path), f"Expected moved file is missing in vault: {path}"


def test_staging_contents():
    expected_staging_files = [
        "/home/user/staging/evil1.txt",
        "/home/user/staging/evil2.txt"
    ]
    for path in expected_staging_files:
        assert os.path.isfile(path), f"Blocked file should still be in staging: {path}"

    unexpected_staging_files = [
        "/home/user/staging/file1.txt",
        "/home/user/staging/file2.txt",
        "/home/user/staging/file3.txt"
    ]
    for path in unexpected_staging_files:
        assert not os.path.exists(path), f"File should have been moved out of staging: {path}"


def test_security_log():
    assert os.path.isfile(LOG), f"Security log missing at {LOG}"
    with open(LOG, "r") as f:
        log_contents = f.read().splitlines()

    expected_lines = [
        "[MOVED] file1.txt -> /home/user/vault/reports/file1.txt",
        "[MOVED] file2.txt -> /home/user/vault/images/file2.txt",
        "[BLOCKED] evil1.txt -> ../../user/evil1.txt",
        "[MOVED] file3.txt -> /home/user/vault/deep/nested/path/file3.txt",
        "[BLOCKED] evil2.txt -> /etc/passwd_copy"
    ]
    for expected_line in expected_lines:
        assert expected_line in log_contents, f"Expected log entry missing: {expected_line}"


def test_map_file_cleaned_up():
    assert not os.path.exists("/home/user/spool/test_batch.map"), "Processed map file was not deleted from spool directory."
    assert not os.path.exists("/home/user/test_batch.map"), "Map file was not moved into spool directory."


def test_daemon_exited():
    try:
        output = subprocess.check_output(["pgrep", "-f", "secure_archiver"]).decode("utf-8")
        if output.strip():
            pytest.fail("secure_archiver daemon is still running, did not exit on SHUTDOWN.")
    except subprocess.CalledProcessError:
        pass


def test_c_source_and_binary_are_real_implementations(tmp_path):
    assert os.path.isfile(SOURCE), f"C source missing at {SOURCE}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "secure_archiver is not a compiled ELF binary"

    text = open(SOURCE, "r", encoding="utf-8", errors="replace").read()
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    assert re.search(r"\binotify_init(?:1)?\s*\(", text), "C source does not initialize inotify"
    assert re.search(r"\binotify_add_watch\s*\(", text), "C source does not add an inotify watch"
    assert "IN_CLOSE_WRITE" in text or "IN_MOVED_TO" in text, "C source does not watch the required events"
    assert re.search(r"\bmmap\s*\(", text), "C source does not use mmap"
    assert re.search(r"\bmunmap\s*\(", text), "C source does not release its mapping"

    rebuilt = str(tmp_path / "secure_archiver_rebuilt")
    result = subprocess.run(
        ["gcc", "-O0", "-std=c11", "-D_GNU_SOURCE", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"secure_archiver.c does not compile:\n{result.stderr}"
    symbols = subprocess.run(["nm", "-D", rebuilt], capture_output=True, text=True, check=True).stdout
    assert re.search(r"\binotify_(?:init|init1)@?", symbols), "Rebuilt source does not call the inotify API"
    assert re.search(r"\binotify_add_watch@?", symbols), "Rebuilt source does not call inotify_add_watch"
    assert re.search(r"\bmmap@?", symbols), "Rebuilt source does not call mmap"


def test_dynamic_daemon_behavior():
    token = uuid.uuid4().hex
    safe1 = f"safe_a_{token}.dat"
    safe2 = f"safe_b_{token}.dat"
    blocked1 = f"blocked_a_{token}.dat"
    blocked2 = f"blocked_b_{token}.dat"
    target1 = f"batch_{token}/discard/../final_a.dat"
    target2 = f"batch_{token}/nested/final_b.dat"
    outside1 = f"../../../../tmp/archiver_escape_{token}"
    outside2 = f"/tmp/archiver_absolute_{token}"
    resolved1 = os.path.normpath(os.path.join(VAULT, target1))
    resolved2 = os.path.normpath(os.path.join(VAULT, target2))
    escaped1 = os.path.normpath(os.path.join(VAULT, outside1))
    escaped2 = outside2

    for name, data in [(safe1, b"dynamic-one"), (safe2, b"dynamic-two"),
                       (blocked1, b"must-stay-one"), (blocked2, b"must-stay-two")]:
        with open(os.path.join(STAGING, name), "wb") as f:
            f.write(data)
    for path in (escaped1, escaped2):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    for entry in os.listdir(SPOOL):
        path = os.path.join(SPOOL, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    with open(LOG, "rb") as f:
        old_log = f.read()

    proc = subprocess.Popen([BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    shutdown = os.path.join(SPOOL, "SHUTDOWN")
    direct_map = os.path.join(SPOOL, f"direct_{token}.map")
    incoming_map = f"/tmp/moved_{token}.map"
    moved_map = os.path.join(SPOOL, os.path.basename(incoming_map))
    try:
        time.sleep(0.5)
        assert proc.poll() is None, "secure_archiver exited before receiving any event"

        # Exercise IN_CLOSE_WRITE by creating a map directly in the watched directory.
        with open(direct_map, "w") as f:
            f.write(f"{safe1}:{target1}\n{blocked1}:{outside1}\n")
        wait_for(lambda: not os.path.exists(direct_map) and os.path.isfile(resolved1))

        # Exercise IN_MOVED_TO with a second, independently generated map.
        with open(incoming_map, "w") as f:
            f.write(f"{safe2}:{target2}\n{blocked2}:{outside2}\n")
        os.rename(incoming_map, moved_map)
        wait_for(lambda: not os.path.exists(moved_map) and os.path.isfile(resolved2))

        with open(shutdown, "w"):
            pass
        proc.wait(timeout=10)
        assert proc.returncode == 0, "secure_archiver did not exit gracefully on SHUTDOWN"
    finally:
        if proc.poll() is None:
            try:
                with open(shutdown, "a"):
                    pass
                proc.wait(timeout=2)
            except Exception:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
        try:
            os.unlink(incoming_map)
        except FileNotFoundError:
            pass

    assert open(resolved1, "rb").read() == b"dynamic-one"
    assert open(resolved2, "rb").read() == b"dynamic-two"
    assert not os.path.exists(os.path.join(STAGING, safe1))
    assert not os.path.exists(os.path.join(STAGING, safe2))
    assert open(os.path.join(STAGING, blocked1), "rb").read() == b"must-stay-one"
    assert open(os.path.join(STAGING, blocked2), "rb").read() == b"must-stay-two"
    assert not os.path.exists(escaped1), "Traversal target escaped the vault"
    assert not os.path.exists(escaped2), "Absolute target escaped the vault"
    assert not os.path.exists(direct_map)
    assert not os.path.exists(moved_map)

    with open(LOG, "rb") as f:
        complete_log = f.read()
    assert complete_log.startswith(old_log), "security.log was replaced instead of appended"
    new_lines = complete_log[len(old_log):].decode("utf-8").splitlines()
    expected = [
        f"[MOVED] {safe1} -> {resolved1}",
        f"[BLOCKED] {blocked1} -> {outside1}",
        f"[MOVED] {safe2} -> {resolved2}",
        f"[BLOCKED] {blocked2} -> {outside2}",
    ]
    assert collections.Counter(new_lines) == collections.Counter(expected), \
        f"Incorrect dynamically generated audit entries: {new_lines!r}"
TEST_EOF

if python3 -m pytest /tmp/test_secure_archiver.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
