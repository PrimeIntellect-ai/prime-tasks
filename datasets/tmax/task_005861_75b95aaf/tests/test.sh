#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import subprocess
import tempfile

import pytest

SOURCE = "/home/user/incremental_backup.c"
EXECUTABLE = "/home/user/incremental_backup"


def test_source_code_exists():
    path = SOURCE
    assert os.path.exists(path), f"Source file {path} is missing."
    assert os.path.isfile(path), f"{path} should be a regular file."


def test_executable_exists():
    path = EXECUTABLE
    assert os.path.exists(path), f"Executable {path} is missing."
    assert os.path.isfile(path), f"{path} should be a regular file."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_backup_err_content():
    path = "/home/user/backup.err"
    assert os.path.exists(path), f"Error log {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "LOCKED: /home/user/data_source/logs/active.log"
    assert expected in content, f"Expected '{expected}' to be in {path}, but got: {content}"


def test_backup_out_content():
    path = "/home/user/backup.out"
    assert os.path.exists(path), f"Output file {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    block_a = "---FILE: /home/user/data_source/config/new_app.conf---\nrecent config data\n"
    block_b = "---FILE: /home/user/data_source/logs/syslog.1---\nlog entry 1\n"

    assert block_a in content, f"Expected block for new_app.conf is missing or malformed in {path}."
    assert block_b in content, f"Expected block for syslog.1 is missing or malformed in {path}."

    assert "old config data" not in content, f"File app.conf should have been excluded based on timestamp."
    assert "active log" not in content, f"File active.log should have been skipped because it was locked."
    assert "---FILE: /home/user/data_source/logs/active.log---" not in content, "active.log should be skipped."
    assert "---FILE: /home/user/data_source/config/app.conf---" not in content, "app.conf should be skipped."


@pytest.fixture(scope="session")
def rebuilt_binary():
    build_dir = tempfile.mkdtemp(prefix="backup-build-")
    output = os.path.join(build_dir, "incremental_backup")
    result = subprocess.run(
        ["gcc", SOURCE, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        "Submitted C source did not compile with gcc:\n"
        + result.stderr.decode("utf-8", errors="replace")
    )
    return output


@pytest.fixture(params=["submitted", "rebuilt"])
def tool(request, rebuilt_binary):
    if request.param == "submitted":
        return EXECUTABLE
    return rebuilt_binary


def run_tool(tool, directory, timestamp):
    return subprocess.run(
        [tool, str(directory), str(timestamp)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def set_mtime(path, timestamp):
    os.utime(path, (timestamp, timestamp))


def test_recursive_incremental_byte_copy_and_ignored_types(tool, tmp_path):
    cutoff = 1800000000
    root = tmp_path / "source"
    nested = root / "one" / "two"
    nested.mkdir(parents=True)

    selected = nested / "selected.bin"
    selected_data = os.urandom(31) + b"\x00binary-data-without-newline"
    selected.write_bytes(selected_data)
    set_mtime(selected, cutoff)  # Equality must be included.

    old_file = root / "old.bin"
    old_file.write_bytes(os.urandom(29))
    set_mtime(old_file, cutoff - 1)

    outside = tmp_path / "outside.bin"
    outside.write_bytes(os.urandom(23))
    set_mtime(outside, cutoff + 10)
    os.symlink(outside, root / "ignored-symlink")
    os.mkfifo(root / "ignored-fifo")

    result = run_tool(tool, root, cutoff)
    expected = b"---FILE: " + os.fsencode(str(selected)) + b"---\n" + selected_data + b"\n"

    assert result.returncode == 0
    assert result.stdout == expected
    assert result.stderr == b""


def test_existing_trailing_newline_is_not_duplicated(tool, tmp_path):
    cutoff = 1810000000
    root = tmp_path / "newline-source"
    root.mkdir()
    selected = root / "already-terminated.txt"
    data = os.urandom(20) + b"\n"
    selected.write_bytes(data)
    set_mtime(selected, cutoff + 1)

    result = run_tool(tool, root, cutoff)
    expected = b"---FILE: " + os.fsencode(str(selected)) + b"---\n" + data

    assert result.returncode == 0
    assert result.stdout == expected
    assert result.stderr == b""


def test_nonblocking_shared_lock_failure(tool, tmp_path):
    cutoff = 1820000000
    root = tmp_path / "locked-source"
    nested = root / "nested"
    nested.mkdir(parents=True)
    locked_path = nested / "actively-written.bin"
    locked_path.write_bytes(os.urandom(37))
    set_mtime(locked_path, cutoff + 1)

    fd = os.open(locked_path, os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = run_tool(tool, root, cutoff)
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)

    expected_err = b"LOCKED: " + os.fsencode(str(locked_path)) + b"\n"
    assert result.returncode == 0
    assert result.stdout == b""
    assert result.stderr == expected_err


def test_requires_exactly_two_arguments(tool, tmp_path):
    no_args = subprocess.run(
        [tool], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    extra_arg = subprocess.run(
        [tool, str(tmp_path), "0", "extra"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert no_args.returncode != 0
    assert extra_arg.returncode != 0
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
