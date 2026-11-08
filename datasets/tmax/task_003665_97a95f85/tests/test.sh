#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile
import pytest


def test_removed_links_file():
    filepath = "/home/user/removed_links.txt"
    assert os.path.isfile(filepath), f"Expected output file {filepath} does not exist."

    with open(filepath, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/backup_source/archive/old/loop_to_root",
        "/home/user/backup_source/projects/alpha/loop_to_projects"
    ]

    assert lines == expected_lines, f"Contents of {filepath} do not match the expected sorted list of removed links. Got: {lines}"


def test_symlinks_deleted():
    loop1 = "/home/user/backup_source/projects/alpha/loop_to_projects"
    loop2 = "/home/user/backup_source/archive/old/loop_to_root"

    assert not os.path.exists(loop1) and not os.path.islink(loop1), f"Symlink {loop1} was not deleted."
    assert not os.path.exists(loop2) and not os.path.islink(loop2), f"Symlink {loop2} was not deleted."


def test_valid_symlink_remains():
    valid_link = "/home/user/backup_source/projects/alpha/readme_link.md"
    assert os.path.islink(valid_link), f"Valid symlink {valid_link} was incorrectly deleted or modified."
    assert os.readlink(valid_link) == "/home/user/backup_source/docs/readme.md", \
        f"Valid symlink {valid_link} has an incorrect target."


def _canonical_archive_name(name):
    while name.startswith("./"):
        name = name[2:]
    if name == "backup_source" or name.startswith("backup_source/"):
        return name.rstrip("/")
    prefix = "/home/user/backup_source"
    if name == prefix or name.startswith(prefix + "/"):
        return ("backup_source" + name[len(prefix):]).rstrip("/")
    return None


def test_archive_created_and_valid():
    archive_path = "/home/user/successful_backup.tar.gz"
    assert os.path.isfile(archive_path), f"Backup archive {archive_path} was not created."

    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            names = tar.getnames()
            members = tar.getmembers()

            # Check that the base directory is included
            assert any(name == "backup_source" or name.startswith("backup_source/") for name in names), \
                "Archive must contain the base directory 'backup_source'."

            # Ensure deleted symlinks are not in the archive
            for name in names:
                assert not name.endswith("loop_to_projects"), f"Archive incorrectly contains deleted link: {name}"
                assert not name.endswith("loop_to_root"), f"Archive incorrectly contains deleted link: {name}"

            # Ensure valid symlink is in the archive
            assert any(name.endswith("readme_link.md") for name in names), \
                "Archive is missing the valid symlink 'readme_link.md'."

            by_name = {}
            for member in members:
                canonical = _canonical_archive_name(member.name)
                if canonical is not None:
                    by_name.setdefault(canonical, []).append(member)

            expected_files = {
                "backup_source/projects/alpha/data.txt": b"Project Alpha Data\n",
                "backup_source/archive/old/data.txt": b"Old Archive\n",
                "backup_source/docs/readme.md": b"Docs\n",
            }

            for path, expected_content in expected_files.items():
                matches = by_name.get(path, [])
                assert len(matches) == 1, f"Archive must contain exactly one entry for {path}."
                member = matches[0]
                assert member.isreg(), f"Archive entry {path} must be a regular file."
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read archived file {path}."
                assert extracted.read() == expected_content, f"Archived file {path} has incorrect contents."

            link_path = "backup_source/projects/alpha/readme_link.md"
            link_matches = by_name.get(link_path, [])
            assert len(link_matches) == 1, f"Archive must contain exactly one entry for {link_path}."
            link_member = link_matches[0]
            assert link_member.issym(), f"Archive entry {link_path} must be stored as a symbolic link."
            assert link_member.linkname == "/home/user/backup_source/docs/readme.md", \
                f"Archived symlink {link_path} has an incorrect target."
    except tarfile.TarError:
        pytest.fail(f"File {archive_path} is not a valid tar.gz archive.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
