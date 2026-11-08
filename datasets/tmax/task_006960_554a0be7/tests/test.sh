#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tarfile
from pathlib import Path

SCRIPT_PATH = "/home/user/service_monitor.py"
LOG_PATH = "/home/user/monitor.log"
BACKUP_PATH = "/home/user/backup.tar.gz"
DATA_PATH = Path("/home/user/app_data")


def test_bashrc_updated():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist"
    with open(bashrc_path, "r") as f:
        content = f.read()
    assert "export MONITOR_MODE=automated" in content, "The environment variable MONITOR_MODE was not exported in .bashrc"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist"


def test_script_missing_env_var():
    env = os.environ.copy()
    env.pop("MONITOR_TARGET_PID", None)
    result = subprocess.run(["python3", SCRIPT_PATH], env=env)
    assert result.returncode == 1, "Script should exit with code 1 when MONITOR_TARGET_PID is missing"


def test_script_running_process():
    dummy_proc = subprocess.Popen(["sleep", "10"])
    env = os.environ.copy()
    env["MONITOR_TARGET_PID"] = str(dummy_proc.pid)

    try:
        result = subprocess.run(["python3", SCRIPT_PATH], env=env)
        assert result.returncode == 0, "Script should exit with code 0 when process is running"

        assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created"
        with open(LOG_PATH, "r") as f:
            lines = f.readlines()
        assert any("[OK] Service running." in line for line in lines), "Success message not found in monitor.log"
    finally:
        dummy_proc.terminate()
        dummy_proc.wait()


def test_script_dead_process():
    if os.path.exists(BACKUP_PATH):
        os.remove(BACKUP_PATH)

    env = os.environ.copy()
    env["MONITOR_TARGET_PID"] = "999999"

    result = subprocess.run(["python3", SCRIPT_PATH], env=env)
    assert result.returncode == 0, "Script should exit with code 0 when process is dead"

    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created"
    with open(LOG_PATH, "r") as f:
        lines = f.readlines()
    assert any("[CRITICAL] Service down. Backup created." in line for line in lines), "Critical message not found in monitor.log"

    assert os.path.isfile(BACKUP_PATH), f"Backup file {BACKUP_PATH} was not created"

    with tarfile.open(BACKUP_PATH, "r:gz") as tar:
        names = tar.getnames()
        assert any("data1.txt" in name for name in names), "data1.txt not found in backup tarball"
        assert any("data2.txt" in name for name in names), "data2.txt not found in backup tarball"


def snapshot_tree(root):
    snapshot = {}
    for path in root.rglob("*"):
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            snapshot[rel] = ("symlink", os.readlink(path))
        elif path.is_dir():
            snapshot[rel] = ("dir", None)
        elif path.is_file():
            snapshot[rel] = ("file", path.read_bytes())
        else:
            raise AssertionError(f"Unsupported file type in app_data: {path}")
    return snapshot


def clean_tar_name(name):
    parts = [part for part in name.split("/") if part not in ("", ".")]
    assert ".." not in parts, f"Unsafe path in backup archive: {name}"
    return "/".join(parts)


def archive_snapshot(tar, base):
    snapshot = {}
    outside = False
    for member in tar.getmembers():
        name = clean_tar_name(member.name)
        if not name:
            continue

        if base:
            if name == base:
                continue
            prefix = base + "/"
            if not name.startswith(prefix):
                outside = True
                continue
            rel = name[len(prefix):]
        else:
            rel = name

        assert rel not in snapshot, f"Duplicate archive member: {rel}"
        if member.isdir():
            snapshot[rel] = ("dir", None)
        elif member.isfile():
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive member: {member.name}"
            snapshot[rel] = ("file", extracted.read())
        elif member.issym():
            snapshot[rel] = ("symlink", member.linkname)
        else:
            snapshot[rel] = ("other", None)
    return None if outside else snapshot


def test_random_dead_pid_and_complete_backup():
    token = secrets.token_hex(12)
    nested = DATA_PATH / ("dynamic_" + token) / "nested"
    nested.mkdir(parents=True)
    (nested / ("payload_" + token + ".bin")).write_bytes(os.urandom(257))
    (DATA_PATH / ("root_" + token + ".txt")).write_text("random fixture " + token, encoding="utf-8")
    (DATA_PATH / ("empty_" + token)).mkdir()
    expected = snapshot_tree(DATA_PATH)

    proc = subprocess.Popen(["sleep", "30"])
    dead_pid = proc.pid
    proc.terminate()
    proc.wait()
    assert not os.path.exists(f"/proc/{dead_pid}"), "Test process PID unexpectedly still exists"

    if os.path.exists(BACKUP_PATH):
        os.remove(BACKUP_PATH)
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    env = os.environ.copy()
    env["MONITOR_TARGET_PID"] = str(dead_pid)
    result = subprocess.run(["python3", SCRIPT_PATH], env=env, timeout=15)
    assert result.returncode == 0, "Script should exit with code 0 for a dynamically selected dead PID"

    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created"
    with open(LOG_PATH, "r") as f:
        lines = f.read().splitlines()
    assert lines and lines[-1] == "[CRITICAL] Service down. Backup created.", "Exact critical message was not appended"
    assert os.path.isfile(BACKUP_PATH), f"Backup file {BACKUP_PATH} was not created"

    with tarfile.open(BACKUP_PATH, "r:gz") as tar:
        members = tar.getmembers()
        bases = [""]
        for member in members:
            name = clean_tar_name(member.name)
            if member.isdir() and name.split("/")[-1:] == ["app_data"]:
                bases.append(name)

        actual_candidates = [archive_snapshot(tar, base) for base in bases]
        assert expected in actual_candidates, "Backup does not exactly contain the entire current app_data directory with correct contents"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
