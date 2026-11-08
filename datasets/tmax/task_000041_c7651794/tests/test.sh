#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import shutil
import stat
import subprocess
import pytest

SCRIPT_PATH = "/home/user/repair.sh"
SYMLINK_PATH = "/home/user/.config/micro-proxy/sites-enabled/default.conf"
EXPECTED_TARGET = "/home/user/.config/micro-proxy/sites-available/default.conf"
LOG_DIR = "/home/user/proxy-logs"


def test_service_status_file():
    status_file = "/home/user/service_status.txt"
    assert os.path.isfile(status_file), f"File {status_file} does not exist."
    with open(status_file, "r") as f:
        content = f.read().strip()
    assert content == "active", f"Expected 'active' in {status_file}, but got '{content}'."


def test_repair_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Repair script {SCRIPT_PATH} does not exist."
    assert not os.path.islink(SCRIPT_PATH), f"Repair script {SCRIPT_PATH} must be a regular file, not a symlink."
    st = os.lstat(SCRIPT_PATH)
    assert stat.S_ISREG(st.st_mode), f"Repair script {SCRIPT_PATH} is not a regular file."
    assert bool(st.st_mode & stat.S_IXUSR), f"Repair script {SCRIPT_PATH} is not executable."


def assert_repairs_applied():
    assert os.path.islink(SYMLINK_PATH), f"{SYMLINK_PATH} is not a symlink."
    assert os.path.exists(SYMLINK_PATH), f"Symlink {SYMLINK_PATH} is broken."
    assert os.path.realpath(SYMLINK_PATH) == os.path.realpath(EXPECTED_TARGET), \
        f"Symlink does not resolve to {EXPECTED_TARGET}."

    result = subprocess.run(
        ["/home/user/scripts/storage-monitor.sh"],
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )
    assert result.returncode == 0, \
        f"Storage quota repair was not applied: {result.stderr.strip()}"


def run_repair_script():
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["XDG_RUNTIME_DIR"] = f"/run/user/{os.getuid()}"
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=20,
    )
    assert result.returncode == 0, \
        f"Repair script failed with exit code {result.returncode}. stdout: {result.stdout!r} stderr: {result.stderr!r}"


def test_repair_script_performs_repairs_and_is_idempotent():
    # Recreate both original faults so the final state alone cannot satisfy this test.
    if os.path.lexists(SYMLINK_PATH):
        if os.path.isdir(SYMLINK_PATH) and not os.path.islink(SYMLINK_PATH):
            shutil.rmtree(SYMLINK_PATH)
        else:
            os.unlink(SYMLINK_PATH)
    os.symlink(
        "/home/user/.config/micro-proxy/sites-available/defualt.conf",
        SYMLINK_PATH,
    )

    shutil.rmtree(LOG_DIR, ignore_errors=True)
    os.makedirs(LOG_DIR, exist_ok=True)
    oversized_log = os.path.join(LOG_DIR, "old_requests.log")
    block = b"\0" * (1024 * 1024)
    with open(oversized_log, "wb") as f:
        for _ in range(60):
            f.write(block)
        f.flush()
        os.fsync(f.fileno())

    before = subprocess.run(
        ["/home/user/scripts/storage-monitor.sh"],
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )
    assert before.returncode != 0, "Verifier failed to recreate the storage-quota fault."
    assert not os.path.exists(SYMLINK_PATH), "Verifier failed to recreate the broken symlink fault."

    run_repair_script()
    assert_repairs_applied()

    # A second invocation must succeed without damaging or undoing the repairs.
    run_repair_script()
    assert_repairs_applied()


def test_symlink_fixed():
    symlink_path = "/home/user/.config/micro-proxy/sites-enabled/default.conf"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    assert os.path.exists(symlink_path), f"Symlink {symlink_path} is broken."

    target = os.readlink(symlink_path)
    expected_target = "/home/user/.config/micro-proxy/sites-available/default.conf"
    # It could be an absolute path or relative path, let's resolve it.
    assert os.path.realpath(symlink_path) == os.path.realpath(expected_target), \
        f"Symlink does not resolve to {expected_target}."


def test_log_quota_fixed():
    log_dir = "/home/user/proxy-logs"
    assert os.path.isdir(log_dir), f"Directory {log_dir} does not exist."

    # Check total size of the directory in MB
    total_size = 0
    for dirpath, _, filenames in os.walk(log_dir):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)

    size_mb = total_size / (1024 * 1024)
    assert size_mb <= 50, f"Log directory size is {size_mb} MB, which still exceeds the 50 MB quota."


def test_service_is_active():
    # Set XDG_RUNTIME_DIR to ensure systemctl --user works
    uid = os.getuid()
    env = os.environ.copy()
    env["XDG_RUNTIME_DIR"] = f"/run/user/{uid}"

    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", "micro-proxy.service"],
            env=env,
            capture_output=True,
            text=True,
            check=False
        )
        assert result.returncode == 0, f"Service micro-proxy.service is not active. Output: {result.stdout.strip()}"
        assert result.stdout.strip() == "active", f"Service is not active, status is '{result.stdout.strip()}'."
    except FileNotFoundError:
        pytest.fail("systemctl command not found.")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
