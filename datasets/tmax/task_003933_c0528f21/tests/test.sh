#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import shutil
import stat
import subprocess
import tempfile
import pytest


def test_backup1_txt():
    path = "/home/user/backups/backup1.txt"
    assert os.path.isfile(path), f"File {path} was not created."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "AAAAABBB", f"Content of {path} is incorrect. Expected 'AAAAABBB', got '{content}'."


def test_backup3_txt():
    path = "/home/user/backups/backup3.txt"
    assert os.path.isfile(path), f"File {path} was not created."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "CC", f"Content of {path} is incorrect. Expected 'CC', got '{content}'."


def test_backup4_skipped():
    path = "/home/user/backups/backup4.txt"
    assert not os.path.exists(path), f"File {path} should not exist because backup4.rle has an invalid magic header."


def test_hardlinks_created():
    path1 = "/home/user/backups/backup1.txt"
    path2 = "/home/user/backups/backup2.txt"
    path5 = "/home/user/backups/backup5.txt"

    assert os.path.isfile(path1), f"Original file {path1} missing."
    assert os.path.isfile(path2), f"Deduplicated file {path2} missing."
    assert os.path.isfile(path5), f"Deduplicated file {path5} missing."

    stat1 = os.stat(path1)
    stat2 = os.stat(path2)
    stat5 = os.stat(path5)

    assert stat1.st_ino == stat2.st_ino, f"{path2} is not a hard link to {path1}."
    assert stat1.st_ino == stat5.st_ino, f"{path5} is not a hard link to {path1}."


def test_log_file():
    log_path = "/home/user/link_count.log"
    assert os.path.isfile(log_path), f"Log file {log_path} was not created."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "2", f"Log file {log_path} contains incorrect count. Expected '2', got '{content}'."


def test_storage_optimizer_source_and_general_behavior():
    source = "/home/user/storage_optimizer.cpp"
    assert os.path.exists(source), f"Required source file {source} does not exist."
    assert stat.S_ISREG(os.lstat(source).st_mode), f"{source} must be a regular file."

    executable = f"/tmp/storage_optimizer_verify_{secrets.token_hex(8)}"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", source, "-o", executable],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "storage_optimizer.cpp did not compile successfully:\n" + compile_result.stderr
    )

    config_path = "/home/user/config.txt"
    log_path = "/home/user/link_count.log"
    original_config = open(config_path, "rb").read()
    original_log_exists = os.path.exists(log_path)
    original_log = open(log_path, "rb").read() if original_log_exists else b""
    archive_dir = tempfile.mkdtemp(prefix="rle_verifier_")

    try:
        magic = "VERIFY_" + secrets.token_hex(10)
        token = secrets.token_hex(5)
        count1 = 10 + secrets.randbelow(15)
        count2 = 2 + secrets.randbelow(7)
        count3 = 3 + secrets.randbelow(8)
        duplicate_rle = f"{count1}Q{count2}R{count3}S"
        duplicate_text = "Q" * count1 + "R" * count2 + "S" * count3

        unique_count = 4 + secrets.randbelow(10)
        unique_rle = f"1X{unique_count}Y2Z"
        unique_text = "X" + "Y" * unique_count + "ZZ"

        duplicate_stems = [
            f"a_{token}_first",
            f"m_{token}_duplicate",
            f"z_{token}_duplicate",
        ]
        unique_stem = f"b_{token}_unique"
        invalid_stem = f"q_{token}_invalid"

        for stem in duplicate_stems:
            with open(os.path.join(archive_dir, stem + ".rle"), "w") as f:
                f.write(magic + "\n" + duplicate_rle + "\n")

        with open(os.path.join(archive_dir, unique_stem + ".rle"), "w") as f:
            f.write(magic + "\n" + unique_rle + "\n")

        with open(os.path.join(archive_dir, invalid_stem + ".rle"), "w") as f:
            f.write("WRONG_" + magic + "\n" + duplicate_rle + "\n")

        # Reverse the original key order and include an unrelated key so the
        # program must actually interpret the key-value configuration.
        with open(config_path, "w") as f:
            f.write(f"UNRELATED_KEY={secrets.token_hex(4)}\n")
            f.write(f"MAGIC_HEADER={magic}\n")
            f.write(f"ARCHIVE_DIR={archive_dir}\n")

        run_result = subprocess.run(
            [executable],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert run_result.returncode == 0, (
            "Compiled storage optimizer failed when executed:\n" + run_result.stderr
        )

        duplicate_paths = [os.path.join(archive_dir, s + ".txt") for s in duplicate_stems]
        for path in duplicate_paths:
            assert os.path.isfile(path), f"Program did not create {path}."
            with open(path, "r") as f:
                assert f.read().strip() == duplicate_text, f"Incorrect decompression in {path}."

        unique_path = os.path.join(archive_dir, unique_stem + ".txt")
        assert os.path.isfile(unique_path), f"Program did not create {unique_path}."
        with open(unique_path, "r") as f:
            assert f.read().strip() == unique_text, f"Incorrect decompression in {unique_path}."

        invalid_path = os.path.join(archive_dir, invalid_stem + ".txt")
        assert not os.path.exists(invalid_path), "Archive with a mismatched magic header was processed."

        duplicate_inodes = [os.stat(path).st_ino for path in duplicate_paths]
        assert len(set(duplicate_inodes)) == 1, "Dynamically generated duplicate files are not hard links."
        assert os.stat(unique_path).st_ino != duplicate_inodes[0], "Different content was incorrectly hard-linked."

        assert os.path.isfile(log_path), "Program did not create /home/user/link_count.log."
        with open(log_path, "r") as f:
            assert f.read().strip() == "2", "Dynamic run reported the wrong hard-link count."
    finally:
        with open(config_path, "wb") as f:
            f.write(original_config)
        if original_log_exists:
            with open(log_path, "wb") as f:
                f.write(original_log)
        elif os.path.exists(log_path):
            os.remove(log_path)
        shutil.rmtree(archive_dir, ignore_errors=True)
        if os.path.exists(executable):
            os.remove(executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
