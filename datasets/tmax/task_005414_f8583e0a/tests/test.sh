#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import posixpath
import stat
import tarfile
import pytest

BASE_DIR = "/home/user/restore/base"
INCR_DIR = "/home/user/restore/incr"
LATEST_DIR = "/home/user/restore/latest"
REPORT_FILE = "/home/user/resolution_report.txt"
BASE_ARCHIVE = "/home/user/backups/base_backup.tar.gz"
INCR_PARTS = [
    "/home/user/backups/incr_backup.tar.gz.part1",
    "/home/user/backups/incr_backup.tar.gz.part2",
]

EXPECTED_BASE_CONTENTS = {
    "config.ini": b"old_config\n",
    "fileA.txt": b"base_data_1\n",
    "fileB.txt": b"unchanged_data\n",
}
EXPECTED_INCR_CONTENTS = {
    "config.ini": b"new_config\n",
    "fileB.txt": b"unchanged_data\n",
    "fileC.txt": b"new_data_1\n",
}


def archive_contents(fileobj=None, path=None):
    if path is not None:
        archive = tarfile.open(path, mode="r:gz")
    else:
        archive = tarfile.open(fileobj=fileobj, mode="r:gz")

    contents = {}
    with archive:
        for member in archive.getmembers():
            if member.isdir():
                continue
            assert member.isfile(), f"Archive entry {member.name!r} is not a regular file."
            name = posixpath.normpath(member.name)
            assert name not in ("", ".")
            assert not name.startswith("/") and name != ".." and not name.startswith("../"), \
                f"Unsafe archive entry {member.name!r}."
            assert name not in contents, f"Duplicate archive entry {name!r}."
            extracted = archive.extractfile(member)
            assert extracted is not None
            contents[name] = extracted.read()
    return contents


@pytest.fixture(scope="session")
def expected_contents():
    assert os.path.isfile(BASE_ARCHIVE), f"Missing base archive {BASE_ARCHIVE}."
    for part in INCR_PARTS:
        assert os.path.isfile(part), f"Missing incremental archive part {part}."

    base = archive_contents(path=BASE_ARCHIVE)
    combined = b"".join(open(part, "rb").read() for part in INCR_PARTS)
    incr = archive_contents(fileobj=io.BytesIO(combined))

    # Ensure the supplied archives still represent the backups created for this task.
    assert base == EXPECTED_BASE_CONTENTS, "The base backup archive was altered or is invalid."
    assert incr == EXPECTED_INCR_CONTENTS, "The incremental backup archive was altered or is invalid."
    return base, incr


def restored_contents(root):
    contents = {}
    for current, dirs, files in os.walk(root, followlinks=False):
        for dirname in dirs:
            path = os.path.join(current, dirname)
            assert stat.S_ISDIR(os.lstat(path).st_mode), f"{path} is not a real directory."
        for filename in files:
            path = os.path.join(current, filename)
            assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} is not a regular file."
            relative = os.path.relpath(path, root).replace(os.sep, "/")
            with open(path, "rb") as handle:
                contents[relative] = handle.read()
    return contents


def test_directories_exist():
    """Check if the required directories exist."""
    assert os.path.isdir(BASE_DIR), f"Directory {BASE_DIR} is missing."
    assert os.path.isdir(INCR_DIR), f"Directory {INCR_DIR} is missing."
    assert os.path.isdir(LATEST_DIR), f"Directory {LATEST_DIR} is missing."


def test_extracted_files_exist():
    """Check if the files are extracted correctly."""
    assert os.path.isfile(os.path.join(BASE_DIR, "fileA.txt")), "fileA.txt missing in base/"
    assert os.path.isfile(os.path.join(BASE_DIR, "fileB.txt")), "fileB.txt missing in base/"
    assert os.path.isfile(os.path.join(BASE_DIR, "config.ini")), "config.ini missing in base/"

    assert os.path.isfile(os.path.join(INCR_DIR, "fileB.txt")), "fileB.txt missing in incr/"
    assert os.path.isfile(os.path.join(INCR_DIR, "config.ini")), "config.ini missing in incr/"
    assert os.path.isfile(os.path.join(INCR_DIR, "fileC.txt")), "fileC.txt missing in incr/"


def test_extracted_contents_match_archives(expected_contents):
    """Validate every restored regular file and its bytes against the supplied archives."""
    expected_base, expected_incr = expected_contents
    assert restored_contents(BASE_DIR) == expected_base, \
        "The base restore does not exactly match base_backup.tar.gz."
    assert restored_contents(INCR_DIR) == expected_incr, \
        "The incremental restore does not exactly match the recombined incremental archive."


def test_hard_links_created():
    """Check if identical files are hard linked."""
    base_fileB = os.path.join(BASE_DIR, "fileB.txt")
    incr_fileB = os.path.join(INCR_DIR, "fileB.txt")

    assert os.path.exists(base_fileB), f"{base_fileB} does not exist."
    assert os.path.exists(incr_fileB), f"{incr_fileB} does not exist."

    stat_base = os.stat(base_fileB)
    stat_incr = os.stat(incr_fileB)

    assert stat_base.st_ino == stat_incr.st_ino, f"{incr_fileB} is not a hard link to {base_fileB}."
    assert stat_base.st_dev == stat_incr.st_dev, f"{incr_fileB} is not on the same filesystem as {base_fileB}."


def test_symlinks_created():
    """Check if symlinks in latest/ point to the correct files."""
    expected_links = {
        "config.ini": os.path.join(INCR_DIR, "config.ini"),
        "fileA.txt": os.path.join(BASE_DIR, "fileA.txt"),
        "fileB.txt": os.path.join(INCR_DIR, "fileB.txt"),
        "fileC.txt": os.path.join(INCR_DIR, "fileC.txt"),
    }

    assert set(os.listdir(LATEST_DIR)) == set(expected_links), \
        "latest/ does not contain exactly one link for every restored filename."

    for filename, expected_target in expected_links.items():
        link_path = os.path.join(LATEST_DIR, filename)
        assert os.path.islink(link_path), f"{link_path} is not a symbolic link."

        # Resolve the symlink to its absolute path
        resolved_target = os.path.realpath(link_path)
        assert resolved_target == expected_target, f"Symlink {link_path} points to {resolved_target}, expected {expected_target}."


def test_resolution_report():
    """Check if the resolution report contains the correct absolute paths."""
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} is missing."

    expected_lines = [
        os.path.join(INCR_DIR, "config.ini"),
        os.path.join(BASE_DIR, "fileA.txt"),
        os.path.join(INCR_DIR, "fileB.txt"),
        os.path.join(INCR_DIR, "fileC.txt")
    ]

    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, f"Report contents are incorrect. Expected {expected_lines}, got {lines}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
