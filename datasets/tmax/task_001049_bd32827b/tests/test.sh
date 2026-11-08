#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT = Path("/home/user/archivist")


def rle(value):
    if not value:
        return ""
    result = []
    current = value[0]
    count = 1
    for char in value[1:]:
        if char == current:
            count += 1
        else:
            result.append(f"{count}{current}")
            current = char
            count = 1
    result.append(f"{count}{current}")
    return "".join(result)


def run_tool(source, backups, name):
    return subprocess.run(
        ["cargo", "run", "--quiet", "--", str(source), str(backups), name],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
        check=True,
    )


def test_project_exists_and_builds():
    assert PROJECT.is_dir(), f"Expected Rust project directory {PROJECT}."
    cargo_toml = PROJECT / "Cargo.toml"
    assert cargo_toml.is_file() and not cargo_toml.is_symlink(), f"Expected a regular {cargo_toml}."
    subprocess.run(
        ["cargo", "build", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
        check=True,
    )


def test_cli_on_derived_arbitrary_inputs():
    token = secrets.token_hex(6)
    with tempfile.TemporaryDirectory(prefix="archivist-test-") as root:
        root = Path(root)
        source = root / f"source_{token}"
        backups = root / f"backups_{token}"
        source.mkdir()
        backups.mkdir()

        changed_name = f"changed_{secrets.token_hex(4)}.txt"
        same_name = f"same_{secrets.token_hex(4)}.txt"
        new_name = f"new_{secrets.token_hex(4)}.txt"
        ignored_name = f"ignored_{secrets.token_hex(4)}.bin"

        random_a = secrets.choice("ABCDEFGH")
        random_b = secrets.choice("uvwxyz")
        changed_v1 = random_a * 7 + "  \n\n" + random_b * 3 + "1111"
        same_value = "M" * 2 + " " * 4 + "\n" * 3 + token + "Z" * 5

        (source / changed_name).write_text(changed_v1, encoding="utf-8")
        (source / same_name).write_text(same_value, encoding="utf-8")
        (source / ignored_name).write_text("AAAA", encoding="utf-8")

        backup_1 = f"snapshot_{secrets.token_hex(5)}"
        backup_2 = f"snapshot_{secrets.token_hex(5)}"
        run_tool(source, backups, backup_1)

        first_dir = backups / backup_1
        assert (first_dir / f"{changed_name}.rle").read_text(encoding="utf-8") == rle(changed_v1)
        assert (first_dir / f"{same_name}.rle").read_text(encoding="utf-8") == rle(same_value)
        assert not (first_dir / f"{ignored_name}.rle").exists()
        assert (backups / "current").is_symlink()
        assert Path(os.readlink(backups / "current")).name == backup_1

        changed_v2 = changed_v1 + "K" * 6 + "\n\n"
        new_value = "P" * 9 + " " + "Q" * 2
        (source / changed_name).write_text(changed_v2, encoding="utf-8")
        (source / new_name).write_text(new_value, encoding="utf-8")
        run_tool(source, backups, backup_2)

        second_dir = backups / backup_2
        changed_1 = first_dir / f"{changed_name}.rle"
        changed_2 = second_dir / f"{changed_name}.rle"
        same_1 = first_dir / f"{same_name}.rle"
        same_2 = second_dir / f"{same_name}.rle"
        new_2 = second_dir / f"{new_name}.rle"

        assert changed_2.read_text(encoding="utf-8") == rle(changed_v2)
        assert same_2.read_text(encoding="utf-8") == rle(same_value)
        assert new_2.read_text(encoding="utf-8") == rle(new_value)
        assert os.stat(changed_1).st_ino != os.stat(changed_2).st_ino
        assert os.stat(same_1).st_ino == os.stat(same_2).st_ino
        assert (backups / "current").is_symlink()
        assert Path(os.readlink(backups / "current")).name == backup_2


def test_cli_requires_exactly_three_arguments():
    for args in ([], ["one", "two"], ["one", "two", "three", "four"]):
        result = subprocess.run(
            ["cargo", "run", "--quiet", "--", *args],
            cwd=PROJECT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert result.returncode != 0, f"CLI accepted {len(args)} arguments instead of exactly three."


def test_current_symlink():
    symlink_path = "/home/user/backups/current"
    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symbolic link."
    target = os.readlink(symlink_path)
    assert os.path.basename(target) == "backup_2", f"Expected symlink to point to backup_2, but points to {target}"


def test_backup_1_file1_content():
    path = "/home/user/backups/backup_1/file1.txt.rle"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    expected = "5A4B1C"
    assert content == expected, f"Content of {path} is '{content}', expected '{expected}'."


def test_backup_2_file1_content():
    path = "/home/user/backups/backup_2/file1.txt.rle"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    expected = "5A4B1C5Z"
    assert content == expected, f"Content of {path} is '{content}', expected '{expected}'."


def test_backup_1_file2_content():
    path = "/home/user/backups/backup_1/file2.txt.rle"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    expected = "4X4Y2Z"
    assert content == expected, f"Content of {path} is '{content}', expected '{expected}'."


def test_backup_2_file2_content():
    path = "/home/user/backups/backup_2/file2.txt.rle"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    expected = "4X4Y2Z"
    assert content == expected, f"Content of {path} is '{content}', expected '{expected}'."


def test_hard_link_for_file2():
    path1 = "/home/user/backups/backup_1/file2.txt.rle"
    path2 = "/home/user/backups/backup_2/file2.txt.rle"
    assert os.path.isfile(path1), f"File {path1} does not exist."
    assert os.path.isfile(path2), f"File {path2} does not exist."
    inode1 = os.stat(path1).st_ino
    inode2 = os.stat(path2).st_ino
    assert inode1 == inode2, f"Expected {path1} and {path2} to be hard linked (same inode), but got {inode1} and {inode2}."


def test_different_inodes_for_file1():
    path1 = "/home/user/backups/backup_1/file1.txt.rle"
    path2 = "/home/user/backups/backup_2/file1.txt.rle"
    assert os.path.isfile(path1), f"File {path1} does not exist."
    assert os.path.isfile(path2), f"File {path2} does not exist."
    inode1 = os.stat(path1).st_ino
    inode2 = os.stat(path2).st_ino
    assert inode1 != inode2, f"Expected {path1} and {path2} to have different inodes, but both have {inode1}."


def test_inode_log_format_and_content():
    log_path = "/home/user/inode_log.txt"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = 4
    assert len(lines) == expected_lines, f"Expected {expected_lines} lines in {log_path}, found {len(lines)}."
    expected_prefixes = ["file1_b1_inode:", "file1_b2_inode:", "file2_b1_inode:", "file2_b2_inode:"]
    files = [
        "/home/user/backups/backup_1/file1.txt.rle",
        "/home/user/backups/backup_2/file1.txt.rle",
        "/home/user/backups/backup_1/file2.txt.rle",
        "/home/user/backups/backup_2/file2.txt.rle",
    ]
    for i in range(4):
        assert lines[i].startswith(expected_prefixes[i]), f"Line {i+1} does not start with '{expected_prefixes[i]}'."
        parts = lines[i].split(":", 1)
        assert len(parts) == 2, f"Line {i+1} is malformed: {lines[i]}"
        logged_inode = parts[1].strip()
        actual_inode = str(os.stat(files[i]).st_ino)
        assert logged_inode == actual_inode, f"Logged inode for {files[i]} was {logged_inode}, expected {actual_inode}."


def test_verify_script_exists_and_runs():
    script = Path("/home/user/verify.sh")
    assert script.is_file() and not script.is_symlink(), f"Expected a regular shell script at {script}."
    result = subprocess.run(
        ["bash", str(script)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=True,
    )
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    prefixes = ["file1_b1_inode:", "file1_b2_inode:", "file2_b1_inode:", "file2_b2_inode:"]
    files = [
        "/home/user/backups/backup_1/file1.txt.rle",
        "/home/user/backups/backup_2/file1.txt.rle",
        "/home/user/backups/backup_1/file2.txt.rle",
        "/home/user/backups/backup_2/file2.txt.rle",
    ]
    assert len(lines) == 4, f"Expected verify.sh to print four lines, got: {result.stdout!r}"
    for line, prefix, path in zip(lines, prefixes, files):
        assert line.startswith(prefix), f"Expected line beginning with {prefix}, got {line!r}"
        assert line.split(":", 1)[1].strip() == str(os.stat(path).st_ino)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
