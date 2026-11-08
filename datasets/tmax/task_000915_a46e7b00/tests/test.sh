#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import pwd
import secrets
import shutil
import stat
import subprocess
import time
import fcntl

SCRIPT_PATH = "/home/user/track_configs.sh"
CONFIG_DIR = "/home/user/configs"
INVENTORY_PATH = "/home/user/config_inventory.txt"


def run_as_user(timeout=10):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        [SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        preexec_fn=demote,
        env={**os.environ, "HOME": account.pw_dir, "USER": "user", "LOGNAME": "user"},
    )


def start_as_user():
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.Popen(
        [SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        preexec_fn=demote,
        env={**os.environ, "HOME": account.pw_dir, "USER": "user", "LOGNAME": "user"},
    )


def read_nonempty_lines():
    with open(INVENTORY_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_01_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f"The script {SCRIPT_PATH} is not executable."


def test_02_script_uses_flock():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "flock" in content, f"The script {SCRIPT_PATH} does not use 'flock' as required."


def test_03_inventory_file_contents():
    assert os.path.isfile(INVENTORY_PATH), f"The inventory file {INVENTORY_PATH} does not exist. Did you run the script?"

    lines = read_nonempty_lines()

    expected_lines = {
        "app_new.json:1.2.3",
        "cache_new.xml:2.0.0-rc1",
        "db_new.csv:9.5.1"
    }

    unexpected_lines = {
        "app_old.json:0.9.0",
        "web_old.xml:1.0.0"
    }

    actual_lines_set = set(lines)

    missing = expected_lines - actual_lines_set
    assert not missing, f"The inventory file is missing expected entries: {missing}"

    extra = actual_lines_set - expected_lines
    assert not extra, f"The inventory file contains unexpected entries (perhaps old files or incorrect parsing): {extra}"


def test_04_dynamic_parsing_recency_appending_and_locking():
    account = pwd.getpwnam("user")
    shutil.rmtree(CONFIG_DIR)
    os.mkdir(CONFIG_DIR, 0o755)
    os.chown(CONFIG_DIR, account.pw_uid, account.pw_gid)

    token = secrets.token_hex(6)
    json_name = f"service_{token}.json"
    csv_name = f"database_{token}.csv"
    xml_name = f"cache_{token}.xml"
    old_name = f"old_{token}.json"

    json_version = f"{secrets.randbelow(80)+10}.{secrets.randbelow(90)+10}.{secrets.randbelow(900)+100}"
    csv_version = f"{secrets.randbelow(70)+20}.{secrets.randbelow(80)+10}.{secrets.randbelow(800)+100}"
    xml_version = f"{secrets.randbelow(60)+30}.{secrets.randbelow(70)+20}.0-rc{secrets.randbelow(8)+1}"
    old_version = f"0.0.{secrets.randbelow(900)+100}"

    with open(os.path.join(CONFIG_DIR, json_name), "w") as f:
        json.dump({"name": "dynamic-service", "version": json_version}, f, indent=2)
    with open(os.path.join(CONFIG_DIR, csv_name), "w") as f:
        f.write(f"key,value\nnotversion,wrong-value\nhost,localhost\nversion,{csv_version}\n")
    with open(os.path.join(CONFIG_DIR, xml_name), "w") as f:
        f.write(f"<config>\n  <name>dynamic-cache</name>\n  <version>{xml_version}</version>\n</config>\n")
    with open(os.path.join(CONFIG_DIR, old_name), "w") as f:
        json.dump({"version": old_version}, f)

    old_time = time.time() - 49 * 60 * 60
    os.utime(os.path.join(CONFIG_DIR, old_name), (old_time, old_time))

    sentinel = f"preexisting_{token}.cfg:keep-{token}"
    with open(INVENTORY_PATH, "w") as f:
        f.write(sentinel + "\n")
    os.chown(INVENTORY_PATH, account.pw_uid, account.pw_gid)
    os.chmod(INVENTORY_PATH, 0o666)

    expected = [
        sentinel,
        f"{json_name}:{json_version}",
        f"{csv_name}:{csv_version}",
        f"{xml_name}:{xml_version}",
    ]

    result = run_as_user()
    assert result.returncode == 0, f"Script failed on dynamic inputs: {result.stderr}"
    actual = read_nonempty_lines()
    assert collections.Counter(actual) == collections.Counter(expected), \
        f"Dynamic run produced incorrect inventory. Expected {expected}, got {actual}"
    assert all(old_name not in line for line in actual), "A file older than 24 hours was included."

    with open(INVENTORY_PATH, "w") as f:
        f.write(sentinel + "\n")
    os.chown(INVENTORY_PATH, account.pw_uid, account.pw_gid)
    os.chmod(INVENTORY_PATH, 0o666)

    lock_fd = os.open(INVENTORY_PATH, os.O_RDWR)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    proc = start_as_user()
    try:
        time.sleep(1.5)
        was_blocked = proc.poll() is None
        while_locked = read_nonempty_lines()
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)

    try:
        stdout, stderr = proc.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        raise AssertionError("Script did not finish after the inventory lock was released.")

    assert was_blocked, "Script did not wait for an exclusive lock held on config_inventory.txt."
    assert while_locked == [sentinel], "Script modified the inventory before obtaining its lock."
    assert proc.returncode == 0, f"Locked script execution failed: {stderr}"
    final_lines = read_nonempty_lines()
    assert collections.Counter(final_lines) == collections.Counter(expected), \
        f"Locked execution produced incorrect inventory. Expected {expected}, got {final_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
