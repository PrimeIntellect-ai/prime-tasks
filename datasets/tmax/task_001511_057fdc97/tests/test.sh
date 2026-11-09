#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import hashlib
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import uuid

import pytest

CREATED_BACKUP = None
DYNAMIC_FILES = {}


def run_monitor_and_validate(binary_path):
    log_dir = "/home/user/app/logs"
    log_path = os.path.join(log_dir, "monitor.log")
    shutil.rmtree(log_dir, ignore_errors=True)

    before = os.statvfs("/home/user/data")
    before_free = before.f_bfree * before.f_frsize
    result = subprocess.run([binary_path], capture_output=True, text=True, timeout=5)
    after = os.statvfs("/home/user/data")
    after_free = after.f_bfree * after.f_frsize

    assert result.returncode == 0, (
        f"Monitor exited with non-zero code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(log_path), f"Log file {log_path} was not created by the monitor program."

    with open(log_path, "r", errors="replace") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines, "Monitor log is empty."
    match = re.fullmatch(r"Free space: ([0-9]+) bytes", lines[-1])
    assert match, f"Monitor did not write the expected free-space record: {lines[-1]!r}"
    reported = int(match.group(1))
    tolerance = 64 * 1024 * 1024
    assert min(before_free, after_free) - tolerance <= reported <= max(before_free, after_free) + tolerance, (
        f"Reported free space {reported} is not consistent with statvfs values "
        f"{before_free} and {after_free}."
    )


def test_monitor_compiled_and_runs():
    binary_path = "/home/user/app/bin/monitor"
    source_path = "/home/user/app/src/monitor.c"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "monitor is not a compiled ELF executable."

    run_monitor_and_validate(binary_path)

    assert os.path.isfile(source_path), f"Source file {source_path} does not exist."
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "monitor")
        build = subprocess.run(
            ["gcc", source_path, "-o", rebuilt], capture_output=True, text=True, timeout=15
        )
        assert build.returncode == 0, f"Fixed monitor source does not compile: {build.stderr}"
        run_monitor_and_validate(rebuilt)


def snapshot_tree(root):
    snapshot = {}
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        rel_dir = os.path.relpath(current, root)
        rel_dir = "" if rel_dir == "." else rel_dir
        for name in dirs:
            path = os.path.join(current, name)
            rel = os.path.join(rel_dir, name)
            if os.path.islink(path):
                snapshot[rel] = ("symlink", os.readlink(path))
            else:
                snapshot[rel] = ("dir", None)
        for name in files:
            path = os.path.join(current, name)
            rel = os.path.join(rel_dir, name)
            if os.path.islink(path):
                snapshot[rel] = ("symlink", os.readlink(path))
            else:
                with open(path, "rb") as f:
                    snapshot[rel] = ("file", hashlib.sha256(f.read()).hexdigest())
    return snapshot


def test_backup_script():
    global CREATED_BACKUP, DYNAMIC_FILES

    script_path = "/home/user/app/scripts/backup.sh"
    assert os.path.isfile(script_path), f"Backup script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Backup script {script_path} is not executable."

    data_dir = "/home/user/data"
    token = uuid.uuid4().hex
    nested_rel = os.path.join("nested_" + token, "payload.bin")
    hidden_rel = ".hidden_" + token
    nested_path = os.path.join(data_dir, nested_rel)
    hidden_path = os.path.join(data_dir, hidden_rel)
    os.makedirs(os.path.dirname(nested_path), mode=0o777, exist_ok=True)
    os.chmod(os.path.dirname(nested_path), 0o777)
    DYNAMIC_FILES = {
        nested_rel: os.urandom(257),
        hidden_rel: ("hidden-" + token).encode(),
    }
    for rel, payload in DYNAMIC_FILES.items():
        with open(os.path.join(data_dir, rel), "wb") as f:
            f.write(payload)
        os.chmod(os.path.join(data_dir, rel), 0o644)

    backup_dir = "/home/user/backups"
    os.makedirs(backup_dir, exist_ok=True)
    for old in glob.glob(os.path.join(backup_dir, "data_backup_*.tar.gz")):
        os.remove(old)
    initial_backups = set(glob.glob(os.path.join(backup_dir, "data_backup_*.tar.gz")))

    started = int(time.time())
    result = subprocess.run(
        ["runuser", "-u", "user", "--", script_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    ended = int(time.time())
    assert result.returncode == 0, (
        f"Backup script failed with exit code {result.returncode}: {result.stderr}"
    )

    current_backups = set(glob.glob(os.path.join(backup_dir, "data_backup_*.tar.gz")))
    new_backups = current_backups - initial_backups
    assert len(new_backups) >= 1, "Backup script did not create a new data_backup_<timestamp>.tar.gz file."

    valid = []
    for path in new_backups:
        match = re.fullmatch(r"data_backup_([0-9]+)\.tar\.gz", os.path.basename(path))
        if match and started - 2 <= int(match.group(1)) <= ended + 2:
            valid.append(path)
    assert valid, "Backup filename does not contain a current Unix epoch timestamp."
    CREATED_BACKUP = max(valid, key=os.path.getmtime)

    with open(CREATED_BACKUP, "rb") as f:
        assert f.read(2) == b"\x1f\x8b", "Backup is not gzip-compressed."
    with tarfile.open(CREATED_BACKUP, mode="r:gz") as archive:
        members = [m for m in archive.getmembers() if m.isfile()]
        assert members, "Backup archive is empty."
        for rel, expected in DYNAMIC_FILES.items():
            normalized_rel = rel.replace(os.sep, "/")
            matches = [
                m for m in members
                if m.name.lstrip("./") == normalized_rel
                or m.name.lstrip("./").endswith("/" + normalized_rel)
            ]
            assert matches, f"Backup archive is missing dynamic file {rel}."
            extracted = archive.extractfile(matches[0])
            assert extracted is not None and extracted.read() == expected, (
                f"Backup archive has incorrect contents for {rel}."
            )


def test_restore_script():
    script_path = "/home/user/app/scripts/restore.sh"
    assert os.path.isfile(script_path), f"Restore script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Restore script {script_path} is not executable."

    no_arg = subprocess.run([script_path], capture_output=True, timeout=10)
    assert no_arg.returncode != 0, "Restore script must reject calls with no arguments."

    backup_dir = "/home/user/backups"
    backups = glob.glob(os.path.join(backup_dir, "data_backup_*.tar.gz"))
    if CREATED_BACKUP and os.path.isfile(CREATED_BACKUP):
        latest_backup = CREATED_BACKUP
    else:
        assert backups, "No backup created for restore testing."
        latest_backup = max(backups, key=os.path.getctime)

    two_args = subprocess.run([script_path, latest_backup, "extra"], capture_output=True, timeout=10)
    assert two_args.returncode != 0, "Restore script must reject calls with more than one argument."

    data_dir = "/home/user/data"
    expected = snapshot_tree(data_dir)
    assert "file1.txt" in expected and "file2.txt" in expected, "Source data files are missing before restore."

    shutil.rmtree(data_dir)
    os.makedirs(os.path.join(data_dir, "stale", "deep"), mode=0o777)
    os.chmod(data_dir, 0o777)
    os.chmod(os.path.join(data_dir, "stale"), 0o777)
    os.chmod(os.path.join(data_dir, "stale", "deep"), 0o777)
    test_file = os.path.join(data_dir, "test_restore_marker.txt")
    hidden_marker = os.path.join(data_dir, ".hidden_restore_marker")
    with open(test_file, "w") as f:
        f.write("marker")
    with open(hidden_marker, "w") as f:
        f.write("hidden marker")
    with open(os.path.join(data_dir, "stale", "deep", "junk"), "w") as f:
        f.write("junk")

    result = subprocess.run([script_path, latest_backup], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"Restore script failed with exit code {result.returncode}: {result.stderr}"
    )

    assert not os.path.exists(test_file), "Restore script did not clear the data directory before extracting."
    assert not os.path.exists(hidden_marker), "Restore script did not clear hidden files before extracting."
    assert os.path.isfile(os.path.join(data_dir, "file1.txt")), "Restored data is missing file1.txt"
    assert os.path.isfile(os.path.join(data_dir, "file2.txt")), "Restored data is missing file2.txt"
    assert snapshot_tree(data_dir) == expected, "Restored directory does not exactly match the backed-up data."


def test_crontab_configured():
    result = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "No crontab found for user."

    crontab_content = result.stdout
    assert "backup.sh" in crontab_content, "backup.sh not found in crontab."

    found_schedule = False
    for line in crontab_content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = stripped.split()
        if len(parts) >= 6 and "backup.sh" in stripped:
            schedule = " ".join(parts[:5])
            command = " ".join(parts[5:])
            if schedule == "0 * * * *" and "/home/user/app/scripts/backup.sh" in command:
                found_schedule = True
                break
    assert found_schedule, (
        "User crontab does not run /home/user/app/scripts/backup.sh at 0 * * * *."
    )


def target_block_directives(content, target):
    directives = []
    pending_header = ""
    in_target = False
    for raw in content.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if not in_target:
            if "{" in line:
                header, remainder = line.split("{", 1)
                header = (pending_header + " " + header).strip()
                pending_header = ""
                targets = header.split()
                in_target = target in targets
                line = remainder.strip()
                if not in_target:
                    continue
            else:
                pending_header = (pending_header + " " + line).strip()
                continue
        if "}" in line:
            before = line.split("}", 1)[0].strip()
            if before:
                directives.append(before.split())
            break
        if line:
            directives.append(line.split())
    return directives


def test_logrotate_config():
    config_path = "/home/user/app/config/logrotate.conf"
    target = "/home/user/app/logs/monitor.log"
    assert os.path.isfile(config_path), f"Logrotate config {config_path} does not exist."

    with open(config_path, "r") as f:
        content = f.read()

    assert target in content, "Logrotate config does not target /home/user/app/logs/monitor.log"
    assert "daily" in content, "Logrotate config missing 'daily'"
    assert "rotate 3" in content, "Logrotate config missing 'rotate 3'"
    assert "compress" in content, "Logrotate config missing 'compress'"
    assert "missingok" in content, "Logrotate config missing 'missingok'"

    directives = target_block_directives(content, target)
    assert directives, "Could not find a logrotate block for monitor.log."
    names = [parts[0] for parts in directives if parts]
    assert "daily" in names, "The monitor.log block is not configured for daily rotation."
    assert "compress" in names, "The monitor.log block does not enable compression."
    assert "missingok" in names, "The monitor.log block does not enable missingok."
    assert any(parts[0] == "rotate" and len(parts) == 2 and parts[1] == "3" for parts in directives), (
        "The monitor.log block does not keep exactly 3 rotations."
    )

    debug = subprocess.run(["logrotate", "--debug", config_path], capture_output=True, text=True, timeout=10)
    assert debug.returncode == 0, f"logrotate rejected the configuration: {debug.stderr}"

    os.makedirs(os.path.dirname(target), exist_ok=True)
    for path in glob.glob(target + "*"):
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)
    token = ("rotate-" + uuid.uuid4().hex).encode()
    with open(target, "wb") as f:
        f.write(token + b"\n")

    with tempfile.TemporaryDirectory() as td:
        state = os.path.join(td, "state")
        rotated = subprocess.run(
            ["logrotate", "-f", "-s", state, config_path],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert rotated.returncode == 0, f"logrotate could not rotate monitor.log: {rotated.stderr}"

        compressed_copy_found = False
        now = time.time()
        for root, dirs, files in os.walk("/home/user"):
            for name in files:
                path = os.path.join(root, name)
                try:
                    if now - os.path.getmtime(path) > 30:
                        continue
                    with gzip.open(path, "rb") as f:
                        if token in f.read():
                            compressed_copy_found = True
                            break
                except (OSError, EOFError):
                    pass
            if compressed_copy_found:
                break
        assert compressed_copy_found, "Forced rotation did not retain a gzip-compressed copy of monitor.log."

        if os.path.exists(target):
            os.remove(target)
        missing_state = os.path.join(td, "missing-state")
        missing = subprocess.run(
            ["logrotate", "-f", "-s", missing_state, config_path],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert missing.returncode == 0, f"missingok was not effective for an absent monitor.log: {missing.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
