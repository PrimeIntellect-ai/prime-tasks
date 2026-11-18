#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import signal
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import uuid

import pytest

SCRIPT_PATH = "/home/user/verify_backup.py"
REPORT_PATH = "/home/user/restore_report.txt"
RESTORE_DIR = "/home/user/restore"
TARGET_ARCHIVE = "/app/staging_backups/backup_bravo79.tar.gz"


def run_sanitizer(path):
    return subprocess.run(["python3", SCRIPT_PATH, path], capture_output=True, timeout=10)


def test_verify_backup_script_exists():
    assert os.path.isfile("/home/user/verify_backup.py"), "verify_backup.py is missing from /home/user/"


def test_verify_backup_clean_corpus():
    script_path = "/home/user/verify_backup.py"
    clean_dir = "/app/corpora/clean/"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(('.tar', '.tar.gz'))]
    assert len(clean_files) > 0, "No clean corpus files found to test"

    failed_files = []
    for f in clean_files:
        result = subprocess.run(["python3", script_path, f], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(f))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected: {failed_files}"


def test_verify_backup_evil_corpus():
    script_path = "/home/user/verify_backup.py"
    evil_dir = "/app/corpora/evil/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(('.tar', '.tar.gz'))]
    assert len(evil_files) > 0, "No evil corpus files found to test"

    failed_files = []
    for f in evil_files:
        result = subprocess.run(["python3", script_path, f], capture_output=True)
        if result.returncode == 0:
            failed_files.append(os.path.basename(f))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed: {failed_files}"


def add_member(tf, name, mode=0o644, data=None):
    if data is None:
        data = os.urandom(17)
    info = tarfile.TarInfo(name)
    info.mode = mode
    info.size = len(data)
    tf.addfile(info, io.BytesIO(data))


def test_verify_backup_generated_hidden_archives():
    # These archives and opaque paths are created only after the agent has run,
    # preventing classification based on the shipped corpus paths or filenames.
    cases = [
        (True, [("documents/" + uuid.uuid4().hex + ".txt", 0o644)]),
        (True, [("nested/path/" + uuid.uuid4().hex, 0o600), ("ordinary.bin", 0o755)]),
        (True, [("..hidden/ordinary", 0o644)]),
        (False, [("/" + uuid.uuid4().hex + "/payload", 0o644)]),
        (False, [("safe/../" + uuid.uuid4().hex, 0o644)]),
        (False, [("../../" + uuid.uuid4().hex, 0o644)]),
        (False, [("bin/" + uuid.uuid4().hex, 0o4755)]),
        (False, [("lib/" + uuid.uuid4().hex, 0o2750)]),
    ]

    with tempfile.TemporaryDirectory(prefix="sanitizer_cases_") as directory:
        generated = []
        for index, (safe, members) in enumerate(cases):
            compressed = index % 2 == 0
            suffix = ".tar.gz" if compressed else ".tar"
            path = os.path.join(directory, uuid.uuid4().hex + suffix)
            mode = "w:gz" if compressed else "w"
            with tarfile.open(path, mode) as tf:
                for name, permissions in members:
                    add_member(tf, name, permissions)
            generated.append((path, safe))

        # Do not expose safety in filenames or invocation order.
        generated.sort(key=lambda item: os.path.basename(item[0]))
        failures = []
        for path, safe in generated:
            result = run_sanitizer(path)
            accepted = result.returncode == 0
            if accepted != safe:
                failures.append((os.path.basename(path), safe, result.returncode))

        assert not failures, f"Generated archive classifications were incorrect: {failures}"


def test_verify_backup_requires_exactly_one_argument():
    no_arg = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, timeout=10)
    two_args = subprocess.run(
        ["python3", SCRIPT_PATH, TARGET_ARCHIVE, TARGET_ARCHIVE],
        capture_output=True,
        timeout=10,
    )
    assert no_arg.returncode != 0, "verify_backup.py accepted zero archive arguments"
    assert two_args.returncode != 0, "verify_backup.py accepted more than one archive argument"


def test_restore_report_content():
    report_path = "/home/user/restore_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing"

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_token = "SYSTEM_RESTORE_SUCCESS_TOKEN_99812"
    assert expected_token in content, f"Report file does not contain the expected token. Found: {content}"


def fetch_report(timeout=2):
    with urllib.request.urlopen("http://127.0.0.1:8080/report", timeout=timeout) as response:
        assert response.status == 200, f"Report endpoint returned HTTP {response.status}"
        return response.read()


def kill_port_8080_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = os.path.join("/proc", entry, "fd")
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
        except (FileNotFoundError, PermissionError):
            continue

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(pids):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.25)


def test_restored_artifacts_and_running_service():
    assert os.path.isfile(TARGET_ARCHIVE), "Target backup archive is missing"
    assert run_sanitizer(TARGET_ARCHIVE).returncode == 0, "The target backup was not accepted as safe"

    disk_path = os.path.join(RESTORE_DIR, "disk.img")
    start_path = os.path.join(RESTORE_DIR, "start_vm.sh")
    assert os.path.isfile(disk_path), "The target disk.img was not restored"
    assert os.path.isfile(start_path), "The target start_vm.sh was not restored"
    assert os.access(start_path, os.X_OK), "The restored start_vm.sh is not executable"

    with tarfile.open(TARGET_ARCHIVE, "r:*") as tf:
        expected_disk = tf.extractfile("disk.img").read()
        expected_start = tf.extractfile("start_vm.sh").read()
    with open(disk_path, "rb") as f:
        assert f.read() == expected_disk, "Restored disk.img does not match the target backup"
    with open(start_path, "rb") as f:
        assert f.read() == expected_start, "Restored start_vm.sh does not match the target backup"

    with open(REPORT_PATH, "rb") as f:
        saved_report = f.read()

    # The instructed background service must still be available when verification begins.
    try:
        live_report = fetch_report()
    except Exception as exc:
        pytest.fail(f"The restored service was not running on port 8080: {exc}")
    assert saved_report == live_report, "restore_report.txt is not the exact HTTP response body"

    # Exercise the restored startup artifact itself after removing the prior listener.
    kill_port_8080_listeners()
    try:
        result = subprocess.run(
            [start_path], cwd=RESTORE_DIR, capture_output=True, timeout=10
        )
        assert result.returncode == 0, f"Restored start_vm.sh failed: {result.stderr.decode(errors='replace')}"

        relaunched_report = None
        deadline = time.time() + 8
        while time.time() < deadline:
            try:
                relaunched_report = fetch_report()
                break
            except Exception:
                time.sleep(0.2)
        assert relaunched_report is not None, "Restored start_vm.sh did not expose the report endpoint"
        assert relaunched_report == saved_report, "Relaunched service response differs from restore_report.txt"
    finally:
        kill_port_8080_listeners()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
