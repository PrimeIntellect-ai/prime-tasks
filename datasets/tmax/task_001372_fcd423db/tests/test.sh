#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import shutil
import stat
import struct
import subprocess
import uuid

import pytest

STATE = {}


def _replace_with_directory(path):
    try:
        mode = os.lstat(path).st_mode
    except FileNotFoundError:
        pass
    else:
        if stat.S_ISDIR(mode) and not stat.S_ISLNK(mode):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    os.makedirs(path)


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    script = "/home/user/deploy_configs.py"
    assert os.path.exists(script), f"{script} is missing."
    mode = os.lstat(script).st_mode
    assert stat.S_ISREG(mode) and not stat.S_ISLNK(mode), f"{script} must be a regular file."

    staging = "/home/user/staging"
    live = "/home/user/live"
    backup = "/home/user/backup"
    for directory in (staging, live, backup):
        _replace_with_directory(directory)

    token = uuid.uuid4().hex[:12]
    deploy_name = f"audit_{token}.conf"
    skip_name = f"audit_skip_{token}.conf"
    STATE["deploy_name"] = deploy_name
    STATE["skip_name"] = skip_name

    staging_files = {
        "app1.conf": "DEPLOY=true\nSETTING1=foo\nSETTING2=bar\n",
        "app2.conf": "DEPLOY=false\nSETTING1=ignore\n",
        "app3.conf": "DEPLOY=true\nSETTING1=baz\n",
        deploy_name: f"DEPLOY=true\nTOKEN={token}\n",
        skip_name: "DEPLOY=trueish\nSETTING1=must_not_deploy\n",
    }
    for name, content in staging_files.items():
        with open(os.path.join(staging, name), "w") as f:
            f.write(content)

    old_app1 = "DEPLOY=true\nSETTING1=old_foo\n"
    old_dynamic = f"DEPLOY=true\nTOKEN=old_{token}\n"
    with open(os.path.join(live, "app1.conf"), "w") as f:
        f.write(old_app1)
    with open(os.path.join(live, deploy_name), "w") as f:
        f.write(old_dynamic)

    STATE["old_app1_stat"] = os.stat(os.path.join(live, "app1.conf"))
    STATE["old_dynamic_stat"] = os.stat(os.path.join(live, deploy_name))
    STATE["dynamic_content"] = staging_files[deploy_name]

    # Existing stale backups ensure the script replaces them before linking.
    with open(os.path.join(backup, "app1.conf.bak"), "w") as f:
        f.write("stale backup\n")
    with open(os.path.join(backup, deploy_name + ".bak"), "w") as f:
        f.write("stale backup\n")

    log_path = "/home/user/deploy.log"
    try:
        os.unlink(log_path)
    except FileNotFoundError:
        pass
    with open(log_path, "w"):
        pass

    # Observe actual rename events in the live directory. Matching inotify
    # cookies prove that each named temporary file was atomically renamed to
    # its final name during this execution.
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    wd = libc.inotify_add_watch(fd, live.encode(), IN_MOVED_FROM | IN_MOVED_TO)
    assert wd >= 0, f"inotify_add_watch failed: errno {ctypes.get_errno()}"

    try:
        result = subprocess.run(
            ["python3", script],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Deployment script exited with {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        data = b""
        while True:
            try:
                chunk = os.read(fd, 65536)
            except BlockingIOError:
                break
            if not chunk:
                break
            data += chunk
    finally:
        os.close(fd)

    moved_from = {}
    moved_to = {}
    offset = 0
    header = struct.Struct("iIII")
    while offset + header.size <= len(data):
        _watch, mask, cookie, name_len = header.unpack_from(data, offset)
        offset += header.size
        raw_name = data[offset:offset + name_len]
        offset += name_len
        name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
        if mask & IN_MOVED_FROM:
            moved_from[cookie] = name
        if mask & IN_MOVED_TO:
            moved_to[cookie] = name

    rename_pairs = {(source, moved_to[cookie]) for cookie, source in moved_from.items()
                    if cookie in moved_to and cookie != 0}
    STATE["rename_pairs"] = rename_pairs


def test_script_used_required_atomic_temp_renames():
    pairs = STATE["rename_pairs"]
    for filename in ("app1.conf", "app3.conf", STATE["deploy_name"]):
        expected = (f".{filename}.tmp", filename)
        assert expected in pairs, f"Did not observe atomic rename {expected[0]} -> {expected[1]}"


def test_live_app1_content():
    path = "/home/user/live/app1.conf"
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "DEPLOY=true" in content, f"{path} is missing DEPLOY=true"
    assert "SETTING1=foo" in content, f"{path} is missing SETTING1=foo"
    assert "SETTING2=bar" in content, f"{path} is missing SETTING2=bar"


def test_live_app3_content():
    path = "/home/user/live/app3.conf"
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "DEPLOY=true" in content, f"{path} is missing DEPLOY=true"
    assert "SETTING1=baz" in content, f"{path} is missing SETTING1=baz"


def test_live_app2_missing():
    path = "/home/user/live/app2.conf"
    assert not os.path.exists(path), f"{path} should not exist because DEPLOY was not true."


def test_backup_app1_content():
    path = "/home/user/backup/app1.conf.bak"
    assert os.path.isfile(path), f"Backup file {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "SETTING1=old_foo" in content, f"Backup file {path} does not contain the old content."


def test_backups_are_hard_links_to_old_live_inodes():
    cases = [
        ("app1.conf.bak", STATE["old_app1_stat"]),
        (STATE["deploy_name"] + ".bak", STATE["old_dynamic_stat"]),
    ]
    for backup_name, old_stat in cases:
        current = os.stat(os.path.join("/home/user/backup", backup_name))
        assert (current.st_dev, current.st_ino) == (old_stat.st_dev, old_stat.st_ino), (
            f"{backup_name} is not a hard link to the old live file inode"
        )


def test_runtime_generated_inputs():
    deployed = os.path.join("/home/user/live", STATE["deploy_name"])
    skipped = os.path.join("/home/user/live", STATE["skip_name"])
    assert os.path.isfile(deployed), f"Runtime-generated deployable file {deployed} is missing"
    with open(deployed) as f:
        assert f.read() == STATE["dynamic_content"]
    assert not os.path.exists(skipped), "A file without the exact DEPLOY=true line was deployed"


def test_staging_files_were_not_moved_away():
    for filename in ("app1.conf", "app2.conf", "app3.conf", STATE["deploy_name"], STATE["skip_name"]):
        assert os.path.isfile(os.path.join("/home/user/staging", filename))


def test_deploy_log():
    path = "/home/user/deploy.log"
    assert os.path.isfile(path), f"Log file {path} is missing."
    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert "Successfully deployed app1.conf" in lines, "Log missing success message for app1.conf"
    assert "Successfully deployed app3.conf" in lines, "Log missing success message for app3.conf"
    assert "Successfully deployed app2.conf" not in lines, "Log incorrectly contains success message for app2.conf"
    assert f"Successfully deployed {STATE['deploy_name']}" in lines
    assert f"Successfully deployed {STATE['skip_name']}" not in lines


def test_no_tmp_files():
    live_dir = "/home/user/live"
    assert os.path.isdir(live_dir), f"Directory {live_dir} is missing."
    for filename in os.listdir(live_dir):
        assert not (filename.startswith(".") and filename.endswith(".tmp")), f"Temporary file {filename} was left in {live_dir}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
