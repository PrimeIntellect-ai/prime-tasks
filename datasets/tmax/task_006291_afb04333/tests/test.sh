#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import subprocess
import tarfile
import time

import pytest

HOME = "/home/user"
APP = f"{HOME}/app_data"
BACKUPS = f"{HOME}/backups"
LOG = f"{HOME}/capacity.log"


def read_log_lines():
    if not os.path.isfile(LOG):
        return []
    with open(LOG, "r", encoding="utf-8", errors="replace") as f:
        return [line.rstrip("\n") for line in f]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def archive_member_data(archive, relative_name):
    wanted = f"app_data/{relative_name}".strip("/")
    with tarfile.open(archive, "r:gz") as tf:
        for member in tf.getmembers():
            normalized = member.name.lstrip("./")
            if normalized == wanted or normalized.endswith("/" + wanted):
                assert member.isfile(), f"Archive member {member.name} is not a regular file"
                extracted = tf.extractfile(member)
                assert extracted is not None
                return extracted.read()
    raise AssertionError(f"{relative_name} was not found in {archive}")


def test_capacity_log_contents():
    """Check that /home/user/capacity.log contains the expected sequence of events."""
    log_path = "/home/user/capacity.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read()

    assert "SERVICE_STARTED" in content, "SERVICE_STARTED not found in capacity.log."

    # Check for CAPACITY_WARNING with a size > 10000000
    warning_match = re.search(r"CAPACITY_WARNING:\s*(\d+)", content)
    assert warning_match is not None, "CAPACITY_WARNING line not found in capacity.log."
    size = int(warning_match.group(1))
    assert size > 10000000, f"CAPACITY_WARNING size {size} is not greater than 10,000,000."

    assert "BACKUP_SUCCESS" in content, "BACKUP_SUCCESS not found in capacity.log."
    assert "RECOVERY_COMPLETE" in content, "RECOVERY_COMPLETE not found in capacity.log."
    assert "SERVICE_STOPPED" in content, "SERVICE_STOPPED not found in capacity.log."

    # Require at least one correctly ordered lifecycle in the submitted final log.
    lines = content.splitlines()
    pos = -1
    predicates = [
        lambda x: x == "SERVICE_STARTED",
        lambda x: re.fullmatch(r"CAPACITY_WARNING: (\d+)", x) is not None and int(x.split(": ", 1)[1]) > 10000000,
        lambda x: x == "BACKUP_SUCCESS",
        lambda x: x == "RECOVERY_COMPLETE",
        lambda x: x == "SERVICE_STOPPED",
    ]
    for predicate in predicates:
        pos = next((i for i in range(pos + 1, len(lines)) if predicate(lines[i])), -1)
        assert pos >= 0, "The required events do not occur in lifecycle order in capacity.log."


def test_backup_archive_exists():
    """Check that the backup archive was created."""
    backup_path = "/home/user/backups/app_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup archive {backup_path} does not exist."


def test_app_data_cleanup():
    """Check that /home/user/app_data was cleaned up and its total size is < 5MB."""
    app_data_path = "/home/user/app_data"
    assert os.path.isdir(app_data_path), f"Directory {app_data_path} does not exist."

    total_size = 0
    for dirpath, _, filenames in os.walk(app_data_path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)

    assert total_size < 5000000, f"Total size of {app_data_path} is {total_size} bytes, which is not less than 5MB. Cleanup may have failed."


def test_required_artifacts_and_workload_behavior():
    required = [
        f"{HOME}/backup.sh",
        f"{HOME}/monitor.cpp",
        f"{HOME}/monitor",
        f"{HOME}/service_manager.sh",
        f"{HOME}/workload.sh",
    ]
    for path in required:
        assert os.path.isfile(path), f"Required artifact {path} is missing"

    for path in [f"{HOME}/backup.sh", f"{HOME}/monitor", f"{HOME}/service_manager.sh", f"{HOME}/workload.sh"]:
        assert os.access(path, os.X_OK), f"{path} is not executable"

    with open(f"{HOME}/monitor", "rb") as f:
        assert f.read(4) == b"\x7fELF", "monitor is not a compiled executable"
    with open(f"{HOME}/monitor.cpp", "r", encoding="utf-8", errors="replace") as f:
        assert f.read().strip(), "monitor.cpp is empty"
    with open(f"{HOME}/backup.sh", "r", encoding="utf-8", errors="replace") as f:
        backup_source = f.read()
    assert re.search(r"(?m)^\s*set\s+-[^\n]*e", backup_source), "backup.sh does not enable set -e"

    shutil.rmtree(APP, ignore_errors=True)
    os.makedirs(APP)
    started = time.monotonic()
    subprocess.run([f"{HOME}/workload.sh"], cwd=HOME, check=True, timeout=15)
    elapsed = time.monotonic() - started

    expected_names = [f"data_{i}.dat" for i in range(1, 7)]
    assert sorted(os.listdir(APP)) == expected_names, "workload.sh did not create exactly data_1.dat through data_6.dat"
    for name in expected_names:
        size = os.path.getsize(os.path.join(APP, name))
        assert 2000000 <= size <= 2200000, f"{name} is not a 2MB file (size={size})"
    assert elapsed >= 5.0, "workload.sh did not stage file creation with one-second delays"


def test_backup_script_on_derived_payloads():
    shutil.rmtree(APP, ignore_errors=True)
    shutil.rmtree(BACKUPS, ignore_errors=True)
    os.makedirs(os.path.join(APP, "nested"))
    os.makedirs(BACKUPS)

    payloads = {
        "alpha.dat": os.urandom(65537),
        "nested/beta.dat": os.urandom(32771),
        "keep.txt": os.urandom(4099),
    }
    for relative, data in payloads.items():
        path = os.path.join(APP, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)

    before = len(read_log_lines())
    subprocess.run([f"{HOME}/backup.sh"], cwd=HOME, check=True, timeout=15)
    archive = os.path.join(BACKUPS, "app_backup.tar.gz")
    assert os.path.isfile(archive), "backup.sh did not create the requested archive"

    for relative, expected in payloads.items():
        actual = archive_member_data(archive, relative)
        assert sha256(actual) == sha256(expected), f"Archive data for {relative} is incorrect"

    assert not os.path.exists(os.path.join(APP, "alpha.dat"))
    assert not os.path.exists(os.path.join(APP, "nested/beta.dat"))
    with open(os.path.join(APP, "keep.txt"), "rb") as f:
        assert sha256(f.read()) == sha256(payloads["keep.txt"]), "backup.sh deleted or changed a non-.dat file"
    assert read_log_lines()[before:] == ["BACKUP_SUCCESS"], "backup.sh did not append the exact BACKUP_SUCCESS line"


def test_monitor_and_service_lifecycle_on_derived_payloads():
    shutil.rmtree(APP, ignore_errors=True)
    shutil.rmtree(BACKUPS, ignore_errors=True)
    os.makedirs(APP)
    os.makedirs(BACKUPS)
    pidfile = f"{HOME}/monitor.pid"
    if os.path.exists(pidfile):
        os.remove(pidfile)

    first = os.urandom(6100000)
    second = os.urandom(4100123)
    marker = os.urandom(173)
    expected_size = len(first) + len(second) + len(marker)
    offset = len(read_log_lines())
    started = False

    try:
        subprocess.run([f"{HOME}/service_manager.sh", "start"], cwd=HOME, check=True, timeout=10)
        started = True
        assert os.path.isfile(pidfile), "service_manager.sh start did not create monitor.pid"
        with open(pidfile, "r") as f:
            pid_text = f.read().strip()
        assert re.fullmatch(r"\d+", pid_text), "monitor.pid does not contain a PID"
        pid = int(pid_text)
        assert os.path.exists(f"/proc/{pid}"), "Saved monitor PID is not running"
        assert os.path.realpath(f"/proc/{pid}/exe") == os.path.realpath(f"{HOME}/monitor"), "Saved PID is not the compiled monitor"

        for name, data in [("probe_a.dat", first), ("probe_b.dat", second), ("marker.txt", marker)]:
            with open(os.path.join(APP, name), "wb") as f:
                f.write(data)

        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            new_lines = read_log_lines()[offset:]
            if "RECOVERY_COMPLETE" in new_lines and os.path.isfile(os.path.join(BACKUPS, "app_backup.tar.gz")):
                break
            time.sleep(0.2)
        else:
            pytest.fail("The running monitor did not detect capacity and complete recovery")

        subprocess.run([f"{HOME}/service_manager.sh", "stop"], cwd=HOME, check=True, timeout=10)
        started = False
        assert not os.path.exists(pidfile), "service_manager.sh stop did not remove monitor.pid"

        deadline = time.monotonic() + 3
        while os.path.exists(f"/proc/{pid}") and time.monotonic() < deadline:
            try:
                with open(f"/proc/{pid}/stat", "r") as f:
                    if f.read().split()[2] == "Z":
                        break
            except FileNotFoundError:
                break
            time.sleep(0.1)

        segment = read_log_lines()[offset:]
        events = [line for line in segment if line in {"SERVICE_STARTED", "BACKUP_SUCCESS", "RECOVERY_COMPLETE", "SERVICE_STOPPED"} or line.startswith("CAPACITY_WARNING:")]
        assert events == [
            "SERVICE_STARTED",
            f"CAPACITY_WARNING: {expected_size}",
            "BACKUP_SUCCESS",
            "RECOVERY_COMPLETE",
            "SERVICE_STOPPED",
        ], f"Monitor lifecycle events were missing, fabricated, or out of order: {events}"

        archive = os.path.join(BACKUPS, "app_backup.tar.gz")
        assert sha256(archive_member_data(archive, "probe_a.dat")) == sha256(first)
        assert sha256(archive_member_data(archive, "probe_b.dat")) == sha256(second)
        assert sha256(archive_member_data(archive, "marker.txt")) == sha256(marker)
        assert not os.path.exists(os.path.join(APP, "probe_a.dat"))
        assert not os.path.exists(os.path.join(APP, "probe_b.dat"))
        with open(os.path.join(APP, "marker.txt"), "rb") as f:
            assert sha256(f.read()) == sha256(marker)
    finally:
        if started:
            subprocess.run([f"{HOME}/service_manager.sh", "stop"], cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
TEST_EOF

if timeout 55s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
