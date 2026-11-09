#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import glob
import gzip
import os
import pwd
import re
import shutil
import subprocess
import tempfile
import uuid


def test_systemd_service_fixed():
    service_path = "/home/user/.config/systemd/user/storage-monitor.service"
    assert os.path.exists(service_path), f"Service file missing: {service_path}"

    with open(service_path, 'r') as f:
        content = f.read()

    # Check that After=local-fs.target is in the [Unit] section
    unit_section_match = re.search(r'\[Unit\](.*?)(\[|$)', content, re.DOTALL)
    assert unit_section_match is not None, "Missing [Unit] section in service file"

    unit_section = unit_section_match.group(1)
    assert "After=local-fs.target" in unit_section.replace(" ", ""), "Service file missing 'After=local-fs.target' in [Unit] section"


def test_monitor_script_exists_and_executable():
    script_path = "/home/user/monitor.sh"
    assert os.path.exists(script_path), f"Monitor script missing: {script_path}"
    assert os.path.isfile(script_path), f"{script_path} is not a file"
    assert os.access(script_path, os.X_OK), f"Monitor script is not executable: {script_path}"


def test_logrotate_conf():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.exists(conf_path), f"Logrotate config missing: {conf_path}"

    with open(conf_path, 'r') as f:
        content = f.read().lower()

    assert "size 100" in content or "size=100" in content, "logrotate.conf missing 'size 100'"
    assert "rotate 5" in content or "rotate=5" in content, "logrotate.conf missing 'rotate 5'"
    assert "compress" in content, "logrotate.conf missing 'compress'"
    assert "missingok" in content, "logrotate.conf missing 'missingok'"
    assert "/home/user/storage-monitor.log" in content, "logrotate.conf must specify the correct log file"


def test_logrotate_success():
    rotated_log_path = "/home/user/storage-monitor.log.1.gz"
    assert os.path.exists(rotated_log_path), f"Rotated log file missing: {rotated_log_path}. Did you run the script, append 150 bytes, and run logrotate?"


def _save_path(path, backup_dir):
    if not os.path.lexists(path):
        return None
    destination = os.path.join(backup_dir, str(uuid.uuid4()))
    shutil.move(path, destination)
    return destination


def _restore_path(path, saved):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
    if saved is not None:
        shutil.move(saved, path)


def test_monitor_script_behavior():
    script_path = "/home/user/monitor.sh"
    fstab_path = "/home/user/mock_fstab"
    log_path = "/home/user/storage-monitor.log"
    backup_dir = tempfile.mkdtemp(prefix="monitor-verifier-")
    saved_fstab = _save_path(fstab_path, backup_dir)
    saved_log = _save_path(log_path, backup_dir)

    token = uuid.uuid4().hex
    mount_one = f"/home/user/verify_mount_{token}_a"
    mount_two = f"/home/user/verify_mount_{token}_b"
    missing = f"/home/user/verify_missing_{token}"
    os.mkdir(mount_one)
    os.mkdir(mount_two)

    try:
        with open(fstab_path, "w") as f:
            f.write(f"UUID=test1 {mount_one} ext4 defaults 0 0\n")
            f.write(f"UUID=test2 {missing} ext4 defaults 0 0\n")
            f.write(f"UUID=test3 {mount_two} ext4 defaults 0 0\n")
        os.chmod(fstab_path, 0o644)

        expected = {}
        for mount in (mount_one, mount_two):
            output = subprocess.check_output(["df", "-P", mount], text=True)
            expected[mount] = output.strip().splitlines()[-1].split()[-2]

        started = datetime.datetime.now()
        result = subprocess.run(
            ["runuser", "-u", "user", "--", script_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        finished = datetime.datetime.now()
        assert result.returncode == 0, f"monitor.sh failed when executed as user: {result.stderr}"
        assert os.path.isfile(log_path), "monitor.sh did not create storage-monitor.log"

        with open(log_path, "r") as f:
            lines = f.read().splitlines()
        assert len(lines) == 2, f"Expected one entry for each existing mount point, got: {lines!r}"

        observed = {}
        pattern = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (.+): (\d+%)$")
        for line in lines:
            match = pattern.fullmatch(line)
            assert match, f"Incorrect monitoring log format: {line!r}"
            timestamp = datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
            assert started - datetime.timedelta(seconds=2) <= timestamp <= finished + datetime.timedelta(seconds=2), \
                f"Log timestamp is not the execution time: {line!r}"
            mount, usage = match.group(2), match.group(3)
            assert mount not in observed, f"Duplicate entry for mount point {mount}"
            observed[mount] = usage

        assert missing not in observed, "monitor.sh logged a mount point that is not an existing directory"
        assert observed == expected, f"monitor.sh did not report df usage for the fstab mount points: {observed!r} != {expected!r}"
    finally:
        for path in (mount_one, mount_two):
            if os.path.isdir(path):
                os.rmdir(path)
        _restore_path(fstab_path, saved_fstab)
        _restore_path(log_path, saved_log)
        shutil.rmtree(backup_dir, ignore_errors=True)


def test_logrotate_configuration_behavior():
    conf_path = "/home/user/logrotate.conf"
    log_path = "/home/user/storage-monitor.log"
    backup_dir = tempfile.mkdtemp(prefix="logrotate-verifier-")
    saved = {}
    for path in glob.glob(log_path + "*"):
        saved[path] = _save_path(path, backup_dir)

    user_info = pwd.getpwnam("user")
    state_one = f"/home/user/.verify-logrotate-{uuid.uuid4().hex}.state"
    state_two = f"/home/user/.verify-logrotate-{uuid.uuid4().hex}.state"
    payload = b"verification-payload-" + os.urandom(220)

    try:
        with open(log_path, "wb") as f:
            f.write(payload)
        os.chown(log_path, user_info.pw_uid, user_info.pw_gid)

        # Prepopulate five backups. A correct 'rotate 5' rule must discard the
        # oldest one while retaining exactly suffixes 1 through 5.
        for number in range(1, 6):
            path = f"{log_path}.{number}.gz"
            with gzip.open(path, "wb") as f:
                f.write(f"old-backup-{number}".encode())
            os.chown(path, user_info.pw_uid, user_info.pw_gid)

        result = subprocess.run(
            ["runuser", "-u", "user", "--", "logrotate", "-s", state_one, conf_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, f"logrotate failed with the submitted config: {result.stderr}"

        rotated = f"{log_path}.1.gz"
        assert os.path.isfile(rotated), "The oversized storage-monitor.log was not rotated and compressed"
        with gzip.open(rotated, "rb") as f:
            assert f.read() == payload, "The compressed .1 backup does not contain the oversized log"
        for number in range(1, 6):
            assert os.path.isfile(f"{log_path}.{number}.gz"), f"Expected rotated backup .{number}.gz"
        assert not os.path.exists(f"{log_path}.6.gz"), "logrotate config retained more than 5 backups"

        # Validate missingok by invoking the real configuration with no active log.
        if os.path.lexists(log_path):
            os.remove(log_path)
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "logrotate", "-s", state_two, conf_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, f"logrotate config errors when the log is missing: {result.stderr}"
    finally:
        for path in glob.glob(log_path + "*"):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)
        for path in (state_one, state_two):
            if os.path.lexists(path):
                os.remove(path)
        for original, backup in saved.items():
            _restore_path(original, backup)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
