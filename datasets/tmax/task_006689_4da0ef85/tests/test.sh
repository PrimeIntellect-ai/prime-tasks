#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import stat
import tarfile
import shutil
import subprocess
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import psutil
import pytest

SCRIPT_FILE = "/home/user/provision.py"
LOG_FILE = "/home/user/provision.log"
BACKUPS_DIR = "/home/user/backups"
APP_DATA_DIR = "/home/user/app_data"
TOKYO = ZoneInfo("Asia/Tokyo")


def _is_exact_server_cmd(cmdline):
    return (
        len(cmdline) == 4
        and os.path.basename(cmdline[0]).startswith("python3")
        and cmdline[1:] == ["-m", "http.server", "9999"]
    )


def _execute_submission():
    assert os.path.isfile(SCRIPT_FILE), f"{SCRIPT_FILE} does not exist or is not a regular file."

    # Remove the requested final state and stop matching servers so the submitted
    # artifact itself must recreate all of it, including the server-start branch.
    for proc in psutil.process_iter(["cmdline"]):
        try:
            if _is_exact_server_cmd(proc.info.get("cmdline") or []):
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except psutil.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=3)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    if os.path.lexists(LOG_FILE):
        os.unlink(LOG_FILE)
    if os.path.lexists(BACKUPS_DIR):
        if os.path.isdir(BACKUPS_DIR) and not os.path.islink(BACKUPS_DIR):
            shutil.rmtree(BACKUPS_DIR)
        else:
            os.unlink(BACKUPS_DIR)

    before = datetime.now(TOKYO)
    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", SCRIPT_FILE],
            cwd="/home/user",
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{SCRIPT_FILE} did not finish within 30 seconds.")
    after = datetime.now(TOKYO)
    assert result.returncode == 0, f"{SCRIPT_FILE} exited with status {result.returncode}."
    return before, after


RUN_STARTED, RUN_FINISHED = _execute_submission()


def _load_log():
    assert os.path.exists(LOG_FILE), f"{LOG_FILE} does not exist."
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{LOG_FILE} is not a valid JSON file.")


def test_provision_log_exists_and_valid():
    log_data = _load_log()
    assert isinstance(log_data, dict), "Provision log must contain a JSON object."
    expected_keys = {"pid", "backup_file", "tz"}
    assert expected_keys.issubset(log_data.keys()), f"JSON must contain keys: {expected_keys}"
    assert set(log_data.keys()) == expected_keys, f"JSON must contain exactly these keys: {expected_keys}"


def test_provision_log_contents():
    log_data = _load_log()

    assert log_data.get("tz") == "Asia/Tokyo", "The 'tz' key must be 'Asia/Tokyo'."

    pid = log_data.get("pid")
    assert isinstance(pid, int) and not isinstance(pid, bool), "The 'pid' key must be an integer."

    try:
        output = subprocess.check_output(["ps", "-p", str(pid), "-o", "args="], text=True).strip()
        assert "python3" in output and "-m" in output and "http.server" in output and "9999" in output, \
            f"Process with PID {pid} is not running the expected command. Found: {output}"
    except subprocess.CalledProcessError:
        pytest.fail(f"Process with PID {pid} is not running.")

    try:
        cmdline = psutil.Process(pid).cmdline()
    except (psutil.NoSuchProcess, psutil.AccessDenied) as exc:
        pytest.fail(f"Cannot inspect server process {pid}: {exc}")
    assert _is_exact_server_cmd(cmdline), f"Process command must be exactly python3 -m http.server 9999; found: {cmdline}"


def test_backup_directory_permissions():
    assert os.path.isdir(BACKUPS_DIR), f"Directory {BACKUPS_DIR} does not exist."
    dir_stat = os.stat(BACKUPS_DIR)
    mode = stat.S_IMODE(dir_stat.st_mode)
    assert mode == 0o700, f"Directory {BACKUPS_DIR} must have 0700 permissions, got {oct(mode)}."


def _source_entries():
    entries = {}

    def visit(directory, prefix=""):
        with os.scandir(directory) as scan:
            for entry in scan:
                rel = f"{prefix}/{entry.name}" if prefix else entry.name
                st = entry.stat(follow_symlinks=False)
                if stat.S_ISLNK(st.st_mode):
                    entries[rel] = ("symlink", os.readlink(entry.path))
                elif stat.S_ISDIR(st.st_mode):
                    entries[rel] = ("directory", None)
                    visit(entry.path, rel)
                elif stat.S_ISREG(st.st_mode):
                    with open(entry.path, "rb") as f:
                        entries[rel] = ("file", f.read())
                else:
                    entries[rel] = ("other", None)

    visit(APP_DATA_DIR)
    return entries


def _relative_archive_name(name):
    parts = [part for part in name.replace("\\", "/").split("/") if part not in ("", ".")]
    if "app_data" in parts:
        parts = parts[parts.index("app_data") + 1:]
    return "/".join(parts)


def test_backup_file_validity():
    log_data = _load_log()

    backup_path = log_data.get("backup_file")
    assert isinstance(backup_path, str), "The 'backup_file' key must be a string."
    assert backup_path.startswith(f"{BACKUPS_DIR}/app_backup_"), "Backup file must start with /home/user/backups/app_backup_"
    assert backup_path.endswith(".tar.gz"), "Backup file must end with .tar.gz"

    match = re.fullmatch(r"/home/user/backups/app_backup_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.tar\.gz", backup_path)
    assert match, "Backup filename must contain a timestamp formatted exactly as YYYY-MM-DD_HH-MM-SS."
    try:
        timestamp = datetime.strptime(match.group(1), "%Y-%m-%d_%H-%M-%S").replace(tzinfo=TOKYO)
    except ValueError:
        pytest.fail("Backup filename contains an invalid Asia/Tokyo date or time.")
    assert RUN_STARTED - timedelta(seconds=1) <= timestamp <= RUN_FINISHED + timedelta(seconds=1), \
        "Backup filename timestamp is not the current Asia/Tokyo time from this provisioning run."

    assert os.path.isfile(backup_path), f"Backup file {backup_path} does not exist."
    assert stat.S_ISREG(os.lstat(backup_path).st_mode), "Backup path must be a regular file."

    file_stat = os.stat(backup_path)
    mode = stat.S_IMODE(file_stat.st_mode)
    assert mode == 0o600, f"Backup file must have 0600 permissions, got {oct(mode)}."

    assert tarfile.is_tarfile(backup_path), f"Backup file {backup_path} is not a valid tarball."

    expected = _source_entries()
    with tarfile.open(backup_path, "r:gz") as tar:
        names = tar.getnames()
        has_config = any(name.endswith("config.yml") for name in names)
        has_data = any(name.endswith("data.txt") for name in names)
        assert has_config, "config.yml not found in the backup tarball."
        assert has_data, "data.txt not found in the backup tarball."

        archived = {}
        for member in tar.getmembers():
            rel = _relative_archive_name(member.name)
            if rel:
                archived[rel] = member

        missing = sorted(set(expected) - set(archived))
        assert not missing, f"Backup is incomplete; missing app_data entries: {missing}"

        for rel, (kind, value) in expected.items():
            member = archived[rel]
            if kind == "directory":
                assert member.isdir(), f"{rel} is not stored as a directory in the backup."
            elif kind == "symlink":
                assert member.issym(), f"{rel} is not stored as a symbolic link in the backup."
                assert member.linkname == value, f"Symbolic link target for {rel} was not preserved."
            elif kind == "file":
                assert member.isfile() or member.islnk(), f"{rel} is not stored as a regular file in the backup."
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read {rel} from the backup."
                assert extracted.read() == value, f"Backup content for {rel} differs from app_data."
            else:
                pytest.fail(f"Unsupported app_data entry was not verifiably backed up: {rel}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
