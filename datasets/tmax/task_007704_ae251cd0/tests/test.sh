#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import shutil
import subprocess
import tempfile
import pytest

def get_directory_size(path):
    total_size = 0
    for dirpath, _, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)
    return total_size

def test_check_quotas_script_exists():
    script_path = "/home/user/check_quotas.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

def test_quota_alerts_log_exists():
    log_path = "/home/user/quota_alerts.log"
    assert os.path.isfile(log_path), f"The log file {log_path} was not created."

def test_quota_alerts_content():
    fstab_path = "/home/user/storage_fstab"
    assert os.path.isfile(fstab_path), f"Missing {fstab_path}"

    expected_alerts = set()
    with open(fstab_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 2:
                continue

            symlink_path = parts[0]
            try:
                quota_mb = int(parts[1])
            except ValueError:
                continue

            if not os.path.exists(symlink_path):
                continue

            real_path = os.path.realpath(symlink_path)
            total_bytes = get_directory_size(real_path)
            actual_mb = total_bytes / 1048576.0

            if actual_mb > quota_mb:
                alert_line = f"[ALERT] Symlink: {symlink_path} | RealDir: {real_path} | Quota: {quota_mb}MB | Actual: {actual_mb:.2f}MB"
                expected_alerts.add(alert_line)

    log_path = "/home/user/quota_alerts.log"
    assert os.path.isfile(log_path), f"Missing {log_path}"

    with open(log_path, "r") as f:
        actual_lines = set(line.strip() for line in f if line.strip())

    missing_alerts = expected_alerts - actual_lines
    extra_alerts = actual_lines - expected_alerts

    assert not missing_alerts, f"Missing expected alerts in {log_path}: {missing_alerts}"
    assert not extra_alerts, f"Found unexpected alerts in {log_path}: {extra_alerts}"

def test_script_executes_against_changed_fixture():
    script_path = "/home/user/check_quotas.py"
    fstab_path = "/home/user/storage_fstab"
    log_path = "/home/user/quota_alerts.log"

    with open(fstab_path, "rb") as f:
        original_fstab = f.read()
    original_log_exists = os.path.isfile(log_path)
    original_log = None
    if original_log_exists:
        with open(log_path, "rb") as f:
            original_log = f.read()

    fixture_root = tempfile.mkdtemp(prefix="quota_verifier_", dir="/home/user")
    links = []
    try:
        real_over = os.path.join(fixture_root, "real_over")
        real_equal = os.path.join(fixture_root, "real_equal")
        real_under = os.path.join(fixture_root, "real_under")
        os.makedirs(os.path.join(real_over, "nested"))
        os.makedirs(real_equal)
        os.makedirs(real_under)

        with open(os.path.join(real_over, "base.bin"), "wb") as f:
            f.truncate(2 * 1048576)
        with open(os.path.join(real_over, "nested", "extra.bin"), "wb") as f:
            f.truncate(262144)
        with open(os.path.join(real_equal, "equal.bin"), "wb") as f:
            f.truncate(3 * 1048576)
        with open(os.path.join(real_under, "under.bin"), "wb") as f:
            f.truncate(524288)

        token = os.path.basename(fixture_root)
        link_over = os.path.join("/home/user/mnt", token + "_over")
        link_equal = os.path.join("/home/user/mnt", token + "_equal")
        link_under = os.path.join("/home/user/mnt", token + "_under")
        for link, target in ((link_over, real_over), (link_equal, real_equal), (link_under, real_under)):
            os.symlink(target, link)
            links.append(link)

        with open(fstab_path, "w") as f:
            f.write(f"{link_over} 2\n")
            f.write(f"{link_equal} 3\n")
            f.write(f"{link_under} 1\n")

        if os.path.exists(log_path):
            os.remove(log_path)

        result = subprocess.run(
            ["python3", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Running {script_path} failed with exit code {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(log_path), f"The script did not create {log_path} when executed."

        expected_alerts = {
            f"[ALERT] Symlink: {link_over} | RealDir: {os.path.realpath(link_over)} | Quota: 2MB | Actual: 2.25MB"
        }
        with open(log_path, "r") as f:
            actual_alerts = set(line.strip() for line in f if line.strip())

        assert actual_alerts == expected_alerts, (
            f"Script output for changed fixture was incorrect. "
            f"Expected {expected_alerts}, got {actual_alerts}"
        )
    finally:
        with open(fstab_path, "wb") as f:
            f.write(original_fstab)
        if original_log_exists:
            with open(log_path, "wb") as f:
                f.write(original_log)
        elif os.path.exists(log_path):
            os.remove(log_path)
        for link in links:
            if os.path.lexists(link):
                os.remove(link)
        shutil.rmtree(fixture_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
