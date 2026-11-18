#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import tarfile
import tempfile
import pytest


def test_summary_json():
    summary_path = "/home/user/summary.json"
    assert os.path.isfile(summary_path), f"Summary file {summary_path} does not exist."

    with open(summary_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {summary_path} is not valid JSON.")

    assert "links_created" in data, "Key 'links_created' missing in summary.json"
    assert "tmp_deleted" in data, "Key 'tmp_deleted' missing in summary.json"
    assert data["links_created"] == 2, f"Expected 2 links_created, got {data['links_created']}"
    assert data["tmp_deleted"] == 4, f"Expected 4 tmp_deleted, got {data['tmp_deleted']}"


def test_hard_links_created():
    file1 = "/home/user/data/file1.txt"
    file2 = "/home/user/data/file2.txt"
    file3 = "/home/user/data/dirA/file3.txt"
    file4 = "/home/user/data/dirA/file4.txt"

    for f in [file1, file2, file3, file4]:
        assert os.path.isfile(f), f"Expected file {f} is missing."

    inode1 = os.stat(file1).st_ino
    inode2 = os.stat(file2).st_ino
    assert inode1 == inode2, f"Files {file1} and {file2} are not hard linked (different inodes)."

    inode3 = os.stat(file3).st_ino
    inode4 = os.stat(file4).st_ino
    assert inode3 == inode4, f"Files {file3} and {file4} are not hard linked (different inodes)."


def test_tmp_files_deleted():
    data_dir = "/home/user/data"
    assert os.path.isdir(data_dir), f"Directory {data_dir} is missing."

    tmp_files_found = []
    for root, dirs, files in os.walk(data_dir):
        for file in files:
            if file.endswith(".tmp"):
                tmp_files_found.append(os.path.join(root, file))

    assert len(tmp_files_found) == 0, f"Found leftover .tmp files: {tmp_files_found}"


def test_archive_exists_and_valid():
    archive_path = "/home/user/data_archive.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            names = tar.getnames()

            basenames = [os.path.basename(n) for n in names if not n.endswith('/')]

            expected_files = ["file1.txt", "file2.txt", "file3.txt", "file4.txt"]
            for ef in expected_files:
                assert ef in basenames, f"Expected file {ef} is missing from the tar archive."

            for name in basenames:
                assert not name.endswith(".tmp"), f"Archived file {name} has a .tmp extension, which should have been deleted."
    except tarfile.ReadError:
        pytest.fail(f"Failed to read {archive_path} as a gzip-compressed tar archive.")


def test_dedup_c_compiles_and_performs_operations():
    source = "/home/user/dedup.c"
    assert os.path.exists(source), f"Required C source {source} does not exist."
    assert stat.S_ISREG(os.lstat(source).st_mode), f"{source} is not a regular source file."

    work = tempfile.mkdtemp(prefix="dedup_verify_")
    executable = os.path.join(work, "dedup_test")
    compiled = subprocess.run(
        ["gcc", source, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compiled.returncode == 0, f"Failed to compile {source}:\n{compiled.stderr}"

    paths = [
        "/home/user/data",
        "/home/user/duplicates.csv",
        "/home/user/summary.json",
    ]
    backups = {}

    def remove_path(path):
        if os.path.islink(path) or os.path.isfile(path):
            os.unlink(path)
        elif os.path.isdir(path):
            shutil.rmtree(path)

    try:
        for index, path in enumerate(paths):
            if os.path.lexists(path):
                backup = os.path.join(work, f"backup_{index}")
                os.rename(path, backup)
                backups[path] = backup

        data_dir = "/home/user/data"
        os.makedirs(os.path.join(data_dir, "nested", "deeper"))

        rng = secrets.SystemRandom()
        link_count = rng.choice([1, 3, 4])
        tmp_count = rng.choice([1, 2, 3, 5, 6])
        token = secrets.token_hex(8)
        pairs = []

        for i in range(link_count):
            directory = data_dir if i % 2 == 0 else os.path.join(data_dir, "nested")
            original = os.path.join(directory, f"original_{token}_{i}.dat")
            duplicate = os.path.join(directory, f"duplicate_{token}_{i}.dat")
            content = f"generated original content {token} {i}\n"
            with open(original, "w") as f:
                f.write(content)
            with open(duplicate, "w") as f:
                f.write(f"content that must be replaced {i}\n")
            pairs.append((original, duplicate, content))

        for i in range(tmp_count):
            directory = os.path.join(data_dir, "nested", "deeper") if i % 2 else data_dir
            with open(os.path.join(directory, f"generated_{token}_{i}.tmp"), "w") as f:
                f.write("temporary data\n")

        keep_file = os.path.join(data_dir, "nested", "keep.tmp.txt")
        with open(keep_file, "w") as f:
            f.write("must remain\n")

        with open("/home/user/duplicates.csv", "w") as f:
            for original, duplicate, _ in pairs:
                f.write(f"{original},{duplicate}\n")

        ran = subprocess.run(
            [executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert ran.returncode == 0, f"Compiled program exited with {ran.returncode}:\n{ran.stderr}"

        for original, duplicate, content in pairs:
            assert os.path.isfile(original), f"Original file disappeared: {original}"
            assert os.path.isfile(duplicate), f"Duplicate was not recreated: {duplicate}"
            assert os.stat(original).st_ino == os.stat(duplicate).st_ino, \
                f"Program did not hard-link {duplicate} to {original}."
            with open(duplicate) as f:
                assert f.read() == content

        remaining_tmp = []
        for root, _, files in os.walk(data_dir):
            remaining_tmp.extend(os.path.join(root, name) for name in files if name.endswith(".tmp"))
        assert not remaining_tmp, f"Program left generated .tmp files: {remaining_tmp}"
        assert os.path.isfile(keep_file), "Program incorrectly deleted a file that does not end in .tmp."

        summary_path = "/home/user/summary.json"
        assert os.path.isfile(summary_path), "Program did not create summary.json."
        with open(summary_path) as f:
            summary_text = f.read()
        expected_text = f'{{"links_created": {link_count}, "tmp_deleted": {tmp_count}}}'
        assert summary_text.strip() == expected_text, \
            f"Expected exact summary {expected_text!r}, got {summary_text.strip()!r}."
        assert json.loads(summary_text) == {
            "links_created": link_count,
            "tmp_deleted": tmp_count,
        }
    finally:
        for path in paths:
            if os.path.lexists(path):
                remove_path(path)
        for path, backup in backups.items():
            os.rename(backup, path)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
