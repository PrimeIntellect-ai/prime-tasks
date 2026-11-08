#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import ctypes
import errno
import json
import os
import select
import shutil
import struct
import subprocess
import tempfile
import time
import uuid

HOME = "/home/user"
SERVER_CONFIGS = os.path.join(HOME, "server_configs")
ACTIVE_CONFIGS = os.path.join(HOME, "active_configs")
INVENTORY = os.path.join(HOME, "config_inventory.json")


def check_original_assertions():
    assert os.path.isdir(ACTIVE_CONFIGS), f"Directory {ACTIVE_CONFIGS} does not exist."

    expected_files = {
        "auth_service_1.5.2.json": {
            "app_name": "Auth Service",
            "config_version": "1.5.2",
            "settings": {"retry": 3},
        },
        "payment_gateway_3.0.json": {
            "app_name": "Payment_Gateway",
            "config_version": "3.0",
            "settings": {"timeout": 30},
        },
    }

    actual_files = set(os.listdir(ACTIVE_CONFIGS))
    expected_filenames = set(expected_files)
    missing = expected_filenames - actual_files
    assert not missing, f"Missing expected files in {ACTIVE_CONFIGS}: {missing}"
    extra = actual_files - expected_filenames
    assert not extra, f"Unexpected files found in {ACTIVE_CONFIGS}: {extra}"

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(ACTIVE_CONFIGS, filename)
        with open(filepath, "r") as f:
            content = json.load(f)
        assert content == expected_content, f"Content of {filename} does not match the original."

    assert os.path.isfile(INVENTORY), f"Inventory file {INVENTORY} does not exist."
    with open(INVENTORY, "r") as f:
        inventory = json.load(f)
    expected_inventory = {
        "auth_service": "1.5.2",
        "payment_gateway": "3.0",
    }
    assert inventory == expected_inventory, (
        f"Inventory content {inventory} does not match expected {expected_inventory}."
    )


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [
            d for d in dirs
            if d not in {"server_configs", "active_configs", "__pycache__", ".cache"}
        ]
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                with open(path, "rb") as f:
                    data = f.read()
                first_line = data.splitlines()[0] if data.splitlines() else b""
                if not (name.endswith(".py") or (first_line.startswith(b"#!") and b"python" in first_line.lower())):
                    continue
                text = data.decode("utf-8")
                compile(text, path, "exec")
                scripts.append(path)
            except (OSError, UnicodeError, SyntaxError):
                continue
    assert scripts, "No Python script was created under /home/user."
    return scripts


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def write_json(path, value, year):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(value, f)
    stamp = time.mktime((year, 6, 15, 12, 0, 0, 0, 0, -1))
    os.utime(path, (stamp, stamp))


def install_fixture(token):
    remove_path(SERVER_CONFIGS)
    remove_path(ACTIVE_CONFIGS)
    remove_path(INVENTORY)
    remove_path(os.path.join(HOME, "config_inventory.tmp.json"))

    app_one = f"Runtime Audit {token}"
    app_two = f"MIXED_Under {token}"
    first = {
        "app_name": app_one,
        "config_version": f"9.{token[-4:]}",
        "settings": {"generated": token},
    }
    second = {
        "app_name": app_two,
        "config_version": 7.25,
        "settings": {"enabled": True},
    }
    write_json(os.path.join(SERVER_CONFIGS, "deep", "one", "target.json"), first, 2023)
    write_json(os.path.join(SERVER_CONFIGS, "other", "target2.json"), second, 2023)
    write_json(
        os.path.join(SERVER_CONFIGS, "invalid", "missing_key.json"),
        {"app_name": "Must Be Ignored", "settings": {}},
        2023,
    )
    write_json(
        os.path.join(SERVER_CONFIGS, "wrong_year", "old.json"),
        {"app_name": "Old Dynamic", "config_version": "1"},
        2022,
    )
    write_json(
        os.path.join(SERVER_CONFIGS, "wrong_year", "new.json"),
        {"app_name": "New Dynamic", "config_version": "2"},
        2024,
    )
    os.makedirs(os.path.join(SERVER_CONFIGS, "misc"), exist_ok=True)
    with open(os.path.join(SERVER_CONFIGS, "misc", "not_json.txt"), "w") as f:
        f.write("irrelevant")

    expected_files = {
        f"runtime_audit_{token.lower()}_{first['config_version']}.json": first,
        f"mixed_under_{token.lower()}_7.25.json": second,
    }
    expected_inventory = {
        f"runtime_audit_{token.lower()}": first["config_version"],
        f"mixed_under_{token.lower()}": 7.25,
    }
    return expected_files, expected_inventory


class MoveWatcher:
    IN_MOVED_TO = 0x00000080

    def __init__(self, directory):
        libc = ctypes.CDLL(None, use_errno=True)
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int
        self.libc = libc
        self.fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "inotify_init1 failed")
        wd = libc.inotify_add_watch(self.fd, os.fsencode(directory), self.IN_MOVED_TO)
        if wd < 0:
            err = ctypes.get_errno()
            os.close(self.fd)
            raise OSError(err, "inotify_add_watch failed")

    def saw_move_to(self, wanted):
        found = False
        while True:
            try:
                data = os.read(self.fd, 65536)
            except OSError as exc:
                if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                    break
                raise
            if not data:
                break
            offset = 0
            while offset + 16 <= len(data):
                _wd, mask, _cookie, length = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + length]
                offset += length
                name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                if (mask & self.IN_MOVED_TO) and name == wanted:
                    found = True
        return found

    def close(self):
        os.close(self.fd)


def validate_dynamic(expected_files, expected_inventory):
    assert os.path.isdir(ACTIVE_CONFIGS), "The script did not create active_configs."
    actual = set(os.listdir(ACTIVE_CONFIGS))
    assert actual == set(expected_files), f"Dynamic output files were {actual}, expected {set(expected_files)}"
    for filename, expected in expected_files.items():
        with open(os.path.join(ACTIVE_CONFIGS, filename), "r") as f:
            assert json.load(f) == expected, f"Incorrect copied content for {filename}"
    assert os.path.isfile(INVENTORY), "The script did not create config_inventory.json."
    with open(INVENTORY, "r") as f:
        assert json.load(f) == expected_inventory, "Incorrect dynamically generated inventory."


def exercise_scripts(scripts):
    backup_root = tempfile.mkdtemp(prefix="config-verifier-backup-")
    original_paths = [SERVER_CONFIGS, ACTIVE_CONFIGS, INVENTORY]
    backups = {}
    try:
        for index, path in enumerate(original_paths):
            if os.path.lexists(path):
                destination = os.path.join(backup_root, str(index))
                os.rename(path, destination)
                backups[path] = destination

        token = uuid.uuid4().hex[:10]
        failures = []
        for script in scripts:
            expected_files, expected_inventory = install_fixture(token)
            watcher = MoveWatcher(HOME)
            try:
                result = subprocess.run(
                    ["python3", script],
                    cwd=HOME,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                moved_atomically = watcher.saw_move_to("config_inventory.json")
            except Exception as exc:
                failures.append(f"{script}: {exc}")
                continue
            finally:
                watcher.close()

            try:
                assert result.returncode == 0, (
                    f"exited {result.returncode}: {result.stderr[-1000:]}"
                )
                validate_dynamic(expected_files, expected_inventory)
                assert moved_atomically, (
                    "config_inventory.json was not installed by an atomic rename/replace operation"
                )
                return
            except AssertionError as exc:
                failures.append(f"{script}: {exc}")

        raise AssertionError("No created Python script satisfied the workflow: " + " | ".join(failures))
    finally:
        for path in original_paths:
            remove_path(path)
        remove_path(os.path.join(HOME, "config_inventory.tmp.json"))
        for path, backup in backups.items():
            os.rename(backup, path)
        shutil.rmtree(backup_root, ignore_errors=True)


check_original_assertions()
scripts = find_python_scripts()
exercise_scripts(scripts)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
