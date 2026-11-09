#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib
import secrets
import subprocess
import sys
import pytest

SCRIPT_PATH = "/home/user/tracker.py"
ACTIVE_PATH = "/home/user/active.conf"
BACKUP_DIR = "/home/user/backups"


def get_expected_redacted_content():
    active_conf_path = ACTIVE_PATH
    assert os.path.exists(active_conf_path), f"{active_conf_path} does not exist"

    with open(active_conf_path, "r") as f:
        lines = f.readlines()

    redacted_lines = []
    for line in lines:
        if line.startswith("password="):
            redacted_lines.append("password=***\n")
        elif line.startswith("token="):
            redacted_lines.append("token=***\n")
        else:
            redacted_lines.append(line)

    return "".join(redacted_lines)


def run_tracker():
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"tracker.py exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def point_active_at(target):
    temporary_link = f"{ACTIVE_PATH}.verifier-{secrets.token_hex(8)}"
    os.symlink(target, temporary_link)
    os.replace(temporary_link, ACTIVE_PATH)


def assert_backup(content):
    digest = hashlib.sha256(content.encode("utf-8")).hexdigest()
    hash_path = os.path.join(BACKUP_DIR, f"{digest}.conf")
    latest_path = os.path.join(BACKUP_DIR, "latest.conf")

    assert os.path.isfile(hash_path), f"Backup file {hash_path} does not exist."
    assert os.path.isfile(latest_path), f"Hard link {latest_path} does not exist."
    with open(hash_path, "r") as f:
        assert f.read() == content

    hash_stat = os.stat(hash_path)
    latest_stat = os.stat(latest_path)
    assert hash_stat.st_ino == latest_stat.st_ino
    assert hash_stat.st_dev == latest_stat.st_dev
    return hash_path


def test_tracker_script_exists():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_backup_files_and_hardlink():
    redacted_content = get_expected_redacted_content()
    expected_hash = hashlib.sha256(redacted_content.encode('utf-8')).hexdigest()

    hash_file_path = f"/home/user/backups/{expected_hash}.conf"
    latest_file_path = "/home/user/backups/latest.conf"

    assert os.path.isfile(hash_file_path), f"Backup file {hash_file_path} does not exist."
    assert os.path.isfile(latest_file_path), f"Hard link {latest_file_path} does not exist."

    with open(hash_file_path, "r") as f:
        actual_content = f.read()
    assert actual_content == redacted_content, f"Content of {hash_file_path} is not correctly redacted."

    stat_hash = os.stat(hash_file_path)
    stat_latest = os.stat(latest_file_path)

    assert stat_hash.st_ino == stat_latest.st_ino, f"{latest_file_path} is not a hard link to {hash_file_path}."
    assert stat_hash.st_dev == stat_latest.st_dev, f"{latest_file_path} and {hash_file_path} are on different devices."


def test_tracker_execution_redaction_deduplication_and_latest_update():
    assert os.path.islink(ACTIVE_PATH), f"{ACTIVE_PATH} is not a symbolic link"
    original_target = os.readlink(ACTIVE_PATH)
    nonce = secrets.token_hex(16)
    config_a = f"/home/user/configs/verifier-{nonce}-a.conf"
    config_b = f"/home/user/configs/verifier-{nonce}-b.conf"

    source_a = (
        f"host=dynamic-{nonce}\n"
        f"password=secret-{nonce}\n"
        " password=not-redacted\n"
        f"token=token-{nonce}\n"
        "xpassword=also-not-redacted\n"
        "user=tester\n"
    )
    redacted_a = (
        f"host=dynamic-{nonce}\n"
        "password=***\n"
        " password=not-redacted\n"
        "token=***\n"
        "xpassword=also-not-redacted\n"
        "user=tester\n"
    )
    source_b = (
        f"host=second-{nonce}\n"
        "token=another-secret\n"
        "password=another-password\n"
        f"mode={nonce}\n"
    )
    redacted_b = (
        f"host=second-{nonce}\n"
        "token=***\n"
        "password=***\n"
        f"mode={nonce}\n"
    )

    try:
        with open(config_a, "w") as f:
            f.write(source_a)
        with open(config_b, "w") as f:
            f.write(source_b)

        point_active_at(config_a)
        run_tracker()
        hash_path_a = assert_backup(redacted_a)

        sentinel = f"must-not-be-overwritten-{nonce}\n"
        with open(hash_path_a, "w") as f:
            f.write(sentinel)

        run_tracker()
        with open(hash_path_a, "r") as f:
            assert f.read() == sentinel, "An existing digest backup was overwritten"
        latest_path = os.path.join(BACKUP_DIR, "latest.conf")
        assert os.stat(hash_path_a).st_ino == os.stat(latest_path).st_ino
        assert os.stat(hash_path_a).st_dev == os.stat(latest_path).st_dev

        point_active_at(config_b)
        run_tracker()
        assert_backup(redacted_b)
    finally:
        point_active_at(original_target)
        for path in (config_a, config_b):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
