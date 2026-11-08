#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import posixpath
import stat
import subprocess
import tarfile
import tempfile
import uuid

import pytest

ARCHIVE_PATH = "/home/user/incremental_backup.tar.gz"
STATE_FILE = "/home/user/backup_state.json"
SOURCE_DIR = "/home/user/images"
CONFIG_PATH = "/home/user/backup.ini"
SCRIPT_PATH = "/home/user/run_backup.py"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def test_script_exists_and_is_regular_file():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} was not created."
    assert not os.path.islink(SCRIPT_PATH), f"Script {SCRIPT_PATH} must be a regular file, not a symlink."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"Script {SCRIPT_PATH} is not a regular file."


def test_archive_contents():
    assert os.path.exists(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} was not created."

    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()
        names = [os.path.basename(m.name) for m in members if m.isfile()]

    expected_names = {"updated.png", "new.png"}
    assert set(names) == expected_names, f"Archive should contain exactly {expected_names}, but found {set(names)}"


def test_state_file_contents():
    assert os.path.exists(STATE_FILE), f"State file {STATE_FILE} does not exist."

    with open(STATE_FILE, "r") as f:
        try:
            state = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"State file {STATE_FILE} is not valid JSON.")

    assert "fake.png" not in state, "fake.png should not be in the state file because it is not a valid PNG."

    expected_files = ["old.png", "updated.png", "new.png"]
    for filename in expected_files:
        assert filename in state, f"{filename} is missing from the state file."

        filepath = os.path.join(SOURCE_DIR, filename)
        actual_mtime = os.path.getmtime(filepath)

        assert state[filename] == actual_mtime, f"mtime for {filename} in state file does not match actual file mtime."


def write_config(source_dir, archive_path, state_file):
    text = (
        "[Backup]\n"
        f"source_dir = {source_dir}\n"
        f"archive_path = {archive_path}\n"
        f"state_file = {state_file}\n"
    )
    with open(CONFIG_PATH, "w") as f:
        f.write(text)


def write_file(path, data, mtime):
    with open(path, "wb") as f:
        f.write(data)
    os.utime(path, (mtime, mtime))


def run_script(cwd):
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Backup script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_state(path):
    with open(path, "r") as f:
        value = json.load(f)
    assert isinstance(value, dict), "State file must contain a JSON object."
    return value


def assert_archive(path, expected):
    assert os.path.isfile(path), f"Archive {path} was not created."
    with tarfile.open(path, "r:gz") as tar:
        members = tar.getmembers()
        assert all(m.isfile() for m in members), "Archive should contain only selected files."
        normalized = []
        for member in members:
            assert not member.name.startswith("/"), "Archive contains an absolute path."
            name = posixpath.normpath(member.name)
            assert name not in ("", ".") and not name.startswith("../"), "Archive contains an unsafe path."
            assert "/" not in name, "Selected files must be stored at the archive root or relative to the source directory."
            normalized.append(name)
        assert len(normalized) == len(set(normalized)), "Archive contains duplicate file entries."
        assert set(normalized) == set(expected), f"Expected archive entries {set(expected)}, found {set(normalized)}"
        for member, name in zip(members, normalized):
            extracted = tar.extractfile(member)
            assert extracted is not None
            assert extracted.read() == expected[name], f"Archived bytes for {name} do not match the source file."


def assert_state(path, expected):
    state = read_state(path)
    assert set(state) == set(expected), f"Expected state entries {set(expected)}, found {set(state)}"
    for name, mtime in expected.items():
        assert isinstance(state[name], (int, float)), f"State mtime for {name} is not numeric."
        assert state[name] == mtime, f"State mtime for {name} does not match the source mtime."


def test_script_behavior_with_fresh_configuration_and_multiple_runs():
    with open(CONFIG_PATH, "rb") as f:
        original_config = f.read()

    try:
        with tempfile.TemporaryDirectory(prefix="backup-verifier-") as root:
            source = os.path.join(root, "source")
            os.mkdir(source)
            archive = os.path.join(root, "result.tar.gz")
            state_path = os.path.join(root, "state.json")
            token = uuid.uuid4().hex

            same = f"same_{token}.txt"
            changed = f"changed_{token}"
            new = f"new_{token}.jpeg"
            future = f"future_{token}.png"
            invalid = f"invalid_{token}.png"
            short = f"short_{token}"

            contents = {
                same: PNG_MAGIC + b"same-data",
                changed: PNG_MAGIC + b"changed-data",
                new: PNG_MAGIC + b"new-data",
                future: PNG_MAGIC + b"future-data",
                invalid: b"NOTAPNG!" + b"invalid-data",
                short: b"\x89PNG",
            }
            mtimes = {
                same: 1700100000.0,
                changed: 1700100100.0,
                new: 1700100200.0,
                future: 1700100300.0,
                invalid: 1700100400.0,
                short: 1700100500.0,
            }
            for name, data in contents.items():
                write_file(os.path.join(source, name), data, mtimes[name])

            initial_state = {
                same: mtimes[same],
                changed: mtimes[changed] - 1.0,
                future: mtimes[future] + 100.0,
                f"deleted_{token}.png": 1600000000.0,
                invalid: 1.0,
            }
            with open(state_path, "w") as f:
                json.dump(initial_state, f)
            first_inode = (os.stat(state_path).st_dev, os.stat(state_path).st_ino)

            write_config(source, archive, state_path)
            run_script(root)

            assert_archive(archive, {changed: contents[changed], new: contents[new]})
            expected_state = {name: mtimes[name] for name in (same, changed, new, future)}
            assert_state(state_path, expected_state)
            second_inode = (os.stat(state_path).st_dev, os.stat(state_path).st_ino)
            assert second_inode != first_inode, "State file was modified in place instead of being atomically replaced."

            run_script(root)
            assert_archive(archive, {})
            assert_state(state_path, expected_state)
            third_inode = (os.stat(state_path).st_dev, os.stat(state_path).st_ino)
            assert third_inode != second_inode, "State file was not atomically replaced on the second run."

            contents[same] = PNG_MAGIC + b"same-data-updated"
            mtimes[same] += 50.0
            write_file(os.path.join(source, same), contents[same], mtimes[same])
            write_file(os.path.join(source, invalid), b"still-not-a-png", mtimes[invalid] + 500.0)

            run_script(root)
            assert_archive(archive, {same: contents[same]})
            expected_state[same] = mtimes[same]
            assert_state(state_path, expected_state)
            fourth_inode = (os.stat(state_path).st_dev, os.stat(state_path).st_ino)
            assert fourth_inode != third_inode, "State file was not atomically replaced after an incremental update."
    finally:
        with open(CONFIG_PATH, "wb") as f:
            f.write(original_config)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
