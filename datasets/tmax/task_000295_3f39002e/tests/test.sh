#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import tarfile
import tempfile
import zipfile
from pathlib import Path

import pytest

ARCHIVE = "/home/user/legacy_docs.zip"
WORKSPACE = "/home/user/workspace"
LOG_PATH = "/home/user/migration.log"

ORIGINAL_FILES = {
    "docs/file1.md": b"# Welcome to OldCorp.\nHere we use [DEPRECATED_MACRO] for formatting.\n",
    "docs/file2.md": b"# OldCorp History\nOldCorp was founded long ago.\n",
    "docs/sub/file3.md": b"Using [DEPRECATED_MACRO] in OldCorp API.\n",
    "docs/file4.txt": b"This text file has [DEPRECATED_MACRO] and OldCorp\n",
}
EXPECTED_TAR_MEMBERS = {
    "docs/",
    "docs/sub/",
    "docs/sub/file3.md",
    "docs/api/",
    "docs/file1.md",
    "docs/file2.md",
    "docs/file4.txt",
}


def load_and_validate_input_archive():
    assert os.path.isfile(ARCHIVE), f"Input archive not found: {ARCHIVE}"
    with zipfile.ZipFile(ARCHIVE, "r") as outer:
        assert outer.namelist() == ["docs_archive.tar.gz"], \
            f"Unexpected outer archive members: {outer.namelist()}"
        nested_data = outer.read("docs_archive.tar.gz")

    with tempfile.NamedTemporaryFile(suffix=".tar.gz") as nested:
        nested.write(nested_data)
        nested.flush()
        with tarfile.open(nested.name, "r:gz") as archive:
            members = archive.getmembers()
            assert len(members) == len(EXPECTED_TAR_MEMBERS), \
                "Nested archive has duplicate or unexpected members"
            assert {member.name for member in members} == EXPECTED_TAR_MEMBERS, \
                f"Unexpected nested archive members: {[m.name for m in members]}"

            for member in members:
                if member.name.endswith("/"):
                    assert member.isdir(), f"Expected directory member: {member.name}"
                else:
                    assert member.isfile(), f"Expected regular file member: {member.name}"
                    extracted = archive.extractfile(member)
                    assert extracted is not None
                    assert extracted.read() == ORIGINAL_FILES[member.name], \
                        f"Unexpected source content for {member.name}"

    return nested_data


def make_expected_workspace(root, nested_data):
    root = Path(root)
    nested_path = root / "docs_archive.tar.gz"
    nested_path.write_bytes(nested_data)

    with tarfile.open(nested_path, "r:gz") as archive:
        archive.extractall(root)

    modified = []
    docs = root / "docs"
    for path in sorted(docs.rglob("*.md")):
        data = path.read_bytes()
        if b"[DEPRECATED_MACRO]" in data:
            path.write_bytes(
                data.replace(b"[DEPRECATED_MACRO]", b"[UPDATED_MACRO]")
                    .replace(b"OldCorp", b"NewCorp")
            )
            modified.append("/home/user/workspace/" + path.relative_to(root).as_posix())
    return modified


def tree_manifest(root):
    root = Path(root)
    assert root.is_dir(), f"Expected directory not found: {root}"
    result = {}
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        for name in dirs + files:
            path = Path(current) / name
            rel = path.relative_to(root).as_posix()
            mode = path.lstat().st_mode
            if stat.S_ISDIR(mode):
                result[rel] = ("directory", None)
            elif stat.S_ISREG(mode):
                result[rel] = ("file", path.read_bytes())
            elif stat.S_ISLNK(mode):
                result[rel] = ("symlink", os.readlink(path))
            else:
                result[rel] = ("other", None)
    return result


def test_complete_extracted_tree_and_contents():
    """Compare the entire workspace with a validated, correctly migrated extraction."""
    nested_data = load_and_validate_input_archive()
    with tempfile.TemporaryDirectory() as temporary:
        expected_log = make_expected_workspace(temporary, nested_data)
        actual = tree_manifest(WORKSPACE)
        expected = tree_manifest(temporary)
        assert actual == expected, "Workspace tree or file contents differ from the migrated archive"

    assert os.path.isfile(LOG_PATH), f"Log file not found at {LOG_PATH}"
    with open(LOG_PATH, "r") as log_file:
        actual_log = [line.strip() for line in log_file if line.strip()]
    assert actual_log == sorted(expected_log), \
        f"migration.log does not list exactly the modified files: {actual_log}"


def test_migration_log_exists_and_content():
    """Verify that migration.log exists and contains the correct sorted paths."""
    log_path = "/home/user/migration.log"
    assert os.path.isfile(log_path), f"Log file not found at {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/workspace/docs/file1.md",
        "/home/user/workspace/docs/sub/file3.md"
    ]
    assert lines == expected_lines, f"migration.log contents incorrect. Expected {expected_lines}, got {lines}"


def test_modified_files():
    """Verify that the targeted files were properly modified."""
    file1 = "/home/user/workspace/docs/file1.md"
    file3 = "/home/user/workspace/docs/sub/file3.md"

    for file_path in [file1, file3]:
        assert os.path.isfile(file_path), f"Expected file not found: {file_path}"
        with open(file_path, "r") as f:
            content = f.read()

        assert "[UPDATED_MACRO]" in content, f"{file_path} missing [UPDATED_MACRO]"
        assert "NewCorp" in content, f"{file_path} missing NewCorp"
        assert "[DEPRECATED_MACRO]" not in content, f"{file_path} still contains [DEPRECATED_MACRO]"
        assert "OldCorp" not in content, f"{file_path} still contains OldCorp"


def test_unmodified_files():
    """Verify that files not meeting the criteria were NOT modified."""
    file2 = "/home/user/workspace/docs/file2.md"
    file4 = "/home/user/workspace/docs/file4.txt"

    assert os.path.isfile(file2), f"Expected file not found: {file2}"
    with open(file2, "r") as f:
        content2 = f.read()

    assert "OldCorp" in content2, f"{file2} should still contain OldCorp"
    assert "NewCorp" not in content2, f"{file2} should not contain NewCorp"

    assert os.path.isfile(file4), f"Expected file not found: {file4}"
    with open(file4, "r") as f:
        content4 = f.read()

    assert "[DEPRECATED_MACRO]" in content4, f"{file4} should still contain [DEPRECATED_MACRO]"
    assert "OldCorp" in content4, f"{file4} should still contain OldCorp"
    assert "[UPDATED_MACRO]" not in content4, f"{file4} should not contain [UPDATED_MACRO]"
    assert "NewCorp" not in content4, f"{file4} should not contain NewCorp"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
