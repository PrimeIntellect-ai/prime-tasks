#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import secrets
import pytest


def get_expected_inode(path):
    return os.stat(path).st_ino


def get_expected_hex(path):
    with open(path, "rb") as f:
        data = f.read(8)
    data = data.ljust(8, b'\x00')
    return data.hex()


def test_tracker_c_exists():
    path = "/home/user/tracker.c"
    assert os.path.isfile(path), f"Source file {path} does not exist."


def test_tracker_binary_exists_and_executable():
    path = "/home/user/tracker"
    assert os.path.isfile(path), f"Executable {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled executable."


def test_tracker_err_output():
    path = "/home/user/tracker_err.txt"
    assert os.path.isfile(path), f"Error output file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "SKIP: /home/user/config_tree/link_loop1",
        "SKIP: /home/user/config_tree/link_broken"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected error line '{expected}' not found in {path}"

    assert len(lines) == len(expected_lines), f"Expected exactly {len(expected_lines)} lines in {path}, but found {len(lines)}"


def test_tracker_out_output():
    path = "/home/user/tracker_out.txt"
    assert os.path.isfile(path), f"Standard output file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    file1 = "/home/user/config_tree/file1.bin"
    file2 = "/home/user/config_tree/file2.bin"
    file3 = "/home/user/config_tree/file3.txt"
    link_ok = "/home/user/config_tree/link_ok"

    expected_lines = [
        f"{file1}|{get_expected_inode(file1)}|{get_expected_hex(file1)}",
        f"{file2}|{get_expected_inode(file2)}|{get_expected_hex(file2)}",
        f"{file3}|{get_expected_inode(file3)}|{get_expected_hex(file3)}",
        f"{link_ok}|{get_expected_inode(file1)}|{get_expected_hex(file1)}"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected output line '{expected}' not found in {path}"

    assert len(lines) == len(expected_lines), f"Expected exactly {len(expected_lines)} lines in {path}, but found {len(lines)}"


def exercise_tracker(binary):
    with tempfile.TemporaryDirectory(prefix="tracker_verify_") as root:
        full = os.path.join(root, "full.bin")
        short = os.path.join(root, "short.bin")
        link_ok = os.path.join(root, "link_ok")
        link_nested = os.path.join(root, "link_nested")
        broken = os.path.join(root, "broken")
        loop1 = os.path.join(root, "loop1")
        loop2 = os.path.join(root, "loop2")
        conf = os.path.join(root, "dynamic.conf")

        with open(full, "wb") as f:
            f.write(secrets.token_bytes(19))
        with open(short, "wb") as f:
            f.write(secrets.token_bytes(5))

        os.symlink("full.bin", link_ok)
        os.symlink("link_ok", link_nested)
        os.symlink("missing-target", broken)
        os.symlink("loop2", loop1)
        os.symlink("loop1", loop2)

        entries = [full, short, link_nested, broken, loop1]
        with open(conf, "w") as f:
            f.write("\n".join(entries) + "\n")

        result = subprocess.run(
            [binary, conf],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )

        expected_stdout = [
            f"{full}|{get_expected_inode(full)}|{get_expected_hex(full)}",
            f"{short}|{get_expected_inode(short)}|{get_expected_hex(short)}",
            f"{link_nested}|{get_expected_inode(full)}|{get_expected_hex(full)}",
        ]
        expected_stderr = [
            f"SKIP: {broken}",
            f"SKIP: {loop1}",
        ]

        assert result.stdout.splitlines() == expected_stdout
        assert result.stderr.splitlines() == expected_stderr


def test_submitted_tracker_on_dynamic_fixture():
    exercise_tracker("/home/user/tracker")


def test_source_builds_and_implements_tracker_behavior():
    with tempfile.TemporaryDirectory(prefix="tracker_build_") as build_dir:
        rebuilt = os.path.join(build_dir, "tracker")
        result = subprocess.run(
            ["gcc", "/home/user/tracker.c", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"tracker.c failed to compile:\n{result.stderr}"
        exercise_tracker(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
