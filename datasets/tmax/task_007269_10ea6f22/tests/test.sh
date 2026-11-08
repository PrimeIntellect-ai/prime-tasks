#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import configparser
import os
import stat
import tarfile
from pathlib import PurePosixPath


def test_symlink_removed():
    symlink_path = "/home/user/data/documents/reports/archive_link"
    assert not os.path.exists(symlink_path) and not os.path.islink(symlink_path), \
        f"The symlink {symlink_path} still exists. It should have been deleted."


def test_loop_symlink_txt_content():
    log_file = "/home/user/loop_symlink.txt"
    assert os.path.isfile(log_file), f"The log file {log_file} does not exist."

    with open(log_file, "r") as f:
        content = f.read().strip()

    expected_path = "/home/user/data/documents/reports/archive_link"
    assert content == expected_path, \
        f"The file {log_file} contains '{content}', but expected '{expected_path}'."


def test_backup_archive_exists_and_valid():
    archive_path = "/home/user/system_backup.tar.gz"
    assert os.path.isfile(archive_path), f"The backup archive {archive_path} does not exist."

    assert tarfile.is_tarfile(archive_path), \
        f"The file {archive_path} is not a valid tar archive."


def test_backup_archive_contents():
    archive_path = "/home/user/system_backup.tar.gz"

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()

        # Check that the symlink is not in the archive
        for name in names:
            assert "archive_link" not in name, \
                f"The archive contains the symlink or a reference to it: {name}"

        # Check that some expected files are present
        # Since the user could tar the directory itself or its contents, we check for basenames or relative paths
        file_basenames = [os.path.basename(name) for name in names]
        expected_files = ["2023_Q1.txt", "2023_Q2.txt", "photo.jpg"]

        for expected in expected_files:
            assert expected in file_basenames, \
                f"Expected file {expected} is missing from the backup archive."


def _source_entries(source_dir):
    entries = {}

    def visit(directory, relative_dir=""):
        with os.scandir(directory) as children:
            for child in children:
                relative = f"{relative_dir}/{child.name}" if relative_dir else child.name
                mode = child.stat(follow_symlinks=False).st_mode
                if stat.S_ISDIR(mode):
                    entries[relative] = ("dir", None)
                    visit(child.path, relative)
                elif stat.S_ISREG(mode):
                    with open(child.path, "rb") as source_file:
                        entries[relative] = ("file", source_file.read())
                elif stat.S_ISLNK(mode):
                    entries[relative] = ("symlink", os.readlink(child.path))
                else:
                    raise AssertionError(f"Unsupported source entry type: {child.path}")

    visit(source_dir)
    return entries


def _normalized_archive_entries(tar, source_dir, prefix):
    normalized = {}

    for member in tar.getmembers():
        path = PurePosixPath(member.name)
        assert not path.is_absolute(), f"Archive contains an absolute member path: {member.name}"
        parts = tuple(part for part in path.parts if part not in ("", "."))
        assert ".." not in parts, f"Archive contains an unsafe member path: {member.name}"

        if prefix:
            if parts == prefix:
                continue
            if parts[:len(prefix)] != prefix:
                return None
            parts = parts[len(prefix):]
        elif not parts:
            continue

        if not parts:
            continue
        relative = "/".join(parts)
        assert relative not in normalized, f"Archive contains duplicate member: {relative}"

        if member.isdir():
            normalized[relative] = ("dir", None)
        elif member.isfile():
            archived_file = tar.extractfile(member)
            assert archived_file is not None, f"Could not read archived file: {member.name}"
            normalized[relative] = ("file", archived_file.read())
        elif member.issym():
            normalized[relative] = ("symlink", member.linkname)
        else:
            raise AssertionError(f"Archive contains an unsupported entry type: {member.name}")

    return normalized


def test_archive_is_complete_snapshot_of_configured_source():
    config = configparser.ConfigParser()
    assert config.read("/home/user/backup.conf"), "Could not read /home/user/backup.conf"
    assert config.has_section("Backup"), "backup.conf is missing the [Backup] section"

    source_dir = os.path.abspath(config.get("Backup", "source_dir"))
    archive_path = os.path.abspath(config.get("Backup", "dest_archive"))
    assert source_dir == "/home/user/data", "The configured source_dir was unexpectedly changed"
    assert archive_path == "/home/user/system_backup.tar.gz", "The configured dest_archive was unexpectedly changed"
    assert os.path.isdir(source_dir), f"Configured source_dir is not a directory: {source_dir}"

    expected_original_files = {
        "documents/reports/2023_Q1.txt": b"Report 1\n",
        "documents/reports/2023_Q2.txt": b"Report 2\n",
        "images/photo.jpg": b"Image data\n",
    }
    for relative, expected_content in expected_original_files.items():
        path = os.path.join(source_dir, *relative.split("/"))
        assert os.path.isfile(path), f"Original source file is missing: {path}"
        with open(path, "rb") as source_file:
            assert source_file.read() == expected_content, f"Original source file was changed: {path}"

    expected = _source_entries(source_dir)
    source_parts = tuple(part for part in source_dir.strip("/").split("/") if part)
    allowed_prefixes = [(), (os.path.basename(source_dir),), source_parts]

    with tarfile.open(archive_path, "r:gz") as tar:
        candidates = []
        for prefix in allowed_prefixes:
            candidate = _normalized_archive_entries(tar, source_dir, prefix)
            if candidate is not None:
                candidates.append(candidate)

    assert any(candidate == expected for candidate in candidates), \
        "The archive is not a complete, content-identical snapshot of the configured source_dir"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
