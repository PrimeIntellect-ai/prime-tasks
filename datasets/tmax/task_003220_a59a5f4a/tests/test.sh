#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import uuid
import pytest


def test_file3_modified():
    file3_path = "/home/user/data/file3.txt"
    assert os.path.isfile(file3_path), f"File {file3_path} does not exist."
    with open(file3_path, "r") as f:
        content = f.read()
    assert "new data v2" in content, f"Content of {file3_path} does not contain expected 'new data v2'. Got: {content}"


def test_backup_v2_hardlinks():
    v1_file1 = "/home/user/backup_v1/file1.txt"
    v2_file1 = "/home/user/backup_v2/file1.txt"
    v1_file2 = "/home/user/backup_v1/file2.txt"
    v2_file2 = "/home/user/backup_v2/file2.txt"

    assert os.path.isfile(v2_file1), f"File {v2_file1} does not exist."
    assert os.path.isfile(v2_file2), f"File {v2_file2} does not exist."

    inode_v1_f1 = os.stat(v1_file1).st_ino
    inode_v2_f1 = os.stat(v2_file1).st_ino
    assert inode_v1_f1 == inode_v2_f1, f"{v2_file1} is not a hard link to {v1_file1}."

    inode_v1_f2 = os.stat(v1_file2).st_ino
    inode_v2_f2 = os.stat(v2_file2).st_ino
    assert inode_v1_f2 == inode_v2_f2, f"{v2_file2} is not a hard link to {v1_file2}."


def test_backup_v2_rev_file():
    rev_file_path = "/home/user/backup_v2/file3.txt.rev"
    assert os.path.isfile(rev_file_path), f"File {rev_file_path} does not exist."
    with open(rev_file_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) >= 1, f"File {rev_file_path} is empty."
    assert lines[0] == "2v atad wen", f"Content of {rev_file_path} is incorrect. Expected '2v atad wen', got: {lines[0]}"


def test_symlink():
    symlink_path = "/home/user/backup_latest"
    target_path = "/home/user/backup_v2"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    target = os.readlink(symlink_path)
    assert target == target_path, f"Symbolic link {symlink_path} points to {target}, expected {target_path}."


def reverse_each_line(data):
    text = data.decode("utf-8")
    output = []
    for line in text.splitlines(keepends=True):
        if line.endswith("\r\n"):
            output.append(line[:-2][::-1] + "\r\n")
        elif line.endswith("\n") or line.endswith("\r"):
            output.append(line[:-1][::-1] + line[-1])
        else:
            output.append(line[::-1])
    return "".join(output).encode("utf-8")


def verify_all_outputs():
    data_dir = "/home/user/data"
    old_dir = "/home/user/backup_v1"
    new_dir = "/home/user/backup_v2"
    assert os.path.isdir(new_dir), "The program did not create /home/user/backup_v2."

    expected_names = set()
    for name in os.listdir(data_dir):
        source = os.path.join(data_dir, name)
        assert os.path.isfile(source), f"Unexpected non-file data entry: {source}"
        with open(source, "rb") as f:
            source_data = f.read()

        old = os.path.join(old_dir, name)
        if os.path.isfile(old):
            with open(old, "rb") as f:
                old_data = f.read()
        else:
            old_data = None

        if old_data == source_data:
            destination = os.path.join(new_dir, name)
            expected_names.add(name)
            assert os.path.isfile(destination), f"Missing hard-linked output for {name}."
            assert os.path.samefile(old, destination), f"{destination} is not a hard link to {old}."
            assert not os.path.lexists(destination + ".rev"), f"Unexpected compressed output for unchanged file {name}."
        else:
            destination = os.path.join(new_dir, name + ".rev")
            expected_names.add(name + ".rev")
            assert os.path.isfile(destination), f"Missing compressed output for {name}."
            with open(destination, "rb") as f:
                actual = f.read()
            assert actual == reverse_each_line(source_data), f"Incorrect compressed content for {name}: {actual!r}"
            assert not os.path.lexists(os.path.join(new_dir, name)), f"Unexpected uncompressed output for changed file {name}."

    assert set(os.listdir(new_dir)) == expected_names, "backup_v2 contains missing or unexpected entries."
    assert os.path.islink("/home/user/backup_latest")
    assert os.readlink("/home/user/backup_latest") == "/home/user/backup_v2"


def run_and_verify(program):
    shutil.rmtree("/home/user/backup_v2", ignore_errors=True)
    result = subprocess.run(
        [program], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f"{program} failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    verify_all_outputs()


def test_z_rust_program_processes_every_file():
    source = "/home/user/archive.rs"
    executable = "/home/user/archive"

    assert os.path.lexists(source), f"{source} does not exist."
    assert stat.S_ISREG(os.lstat(source).st_mode), f"{source} is not a regular Rust source file."
    assert os.path.lexists(executable), f"{executable} does not exist."
    assert stat.S_ISREG(os.lstat(executable).st_mode), f"{executable} is not a regular compiled program."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable} is not an ELF executable."

    token = uuid.uuid4().hex
    unchanged = f"unchanged_{token}.txt"
    changed = f"changed_{token}.txt"
    new_file = f"new_{token}.txt"

    with open(os.path.join("/home/user/data", unchanged), "wb") as f:
        f.write(b"same randomized contents\nsecond line\n")
    with open(os.path.join("/home/user/backup_v1", unchanged), "wb") as f:
        f.write(b"same randomized contents\nsecond line\n")

    with open(os.path.join("/home/user/data", changed), "wb") as f:
        f.write(b"current randomized value\nline two\nlast line")
    with open(os.path.join("/home/user/backup_v1", changed), "wb") as f:
        f.write(b"older different value\n")

    with open(os.path.join("/home/user/data", new_file), "wb") as f:
        f.write(b"brand new randomized value\nmore text\n")

    compiled_from_source = f"/tmp/archive_from_source_{token}"
    compile_result = subprocess.run(
        ["rustc", source, "-o", compiled_from_source],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, (
        f"archive.rs is not valid compilable Rust code: {compile_result.stderr!r}"
    )

    run_and_verify(executable)
    run_and_verify(compiled_from_source)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
