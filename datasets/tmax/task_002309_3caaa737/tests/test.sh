#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import stat
import tarfile

import pytest

WORKSPACE_DIR = "/home/user/project_workspace"
MANIFEST_PATH = "/home/user/manifest.sha256"
CLEAN_ARCHIVE = "/home/user/clean_project.tar.gz"
INCOMING_ARCHIVE = "/home/user/incoming_project.tar.gz"

CSV_CONTENT = b"id,name,value\n1,alpha,100\n2,beta,200\n"
EXPECTED_WORKSPACE = {
    "docs/data_copy.csv": CSV_CONTENT,
    "docs/story1.txt": "El pingüino y el niño\n".encode("utf-8"),
    "docs/story2.txt": "Más camaleón\n".encode("utf-8"),
    "src/data.csv": CSV_CONTENT,
    "src/data_backup.csv": CSV_CONTENT,
}
EXPECTED_INCOMING = {
    "docs/data_copy.csv": CSV_CONTENT,
    "docs/story1.txt": "El pingüino y el niño\n".encode("iso-8859-1"),
    "docs/story2.txt": "Más camaleón\n".encode("iso-8859-1"),
    "src/data.csv": CSV_CONTENT,
    "src/data_backup.csv": CSV_CONTENT,
}
EXPECTED_DIRS = {"docs", "src"}


def get_all_files(directory):
    file_paths = []
    for root, _, files in os.walk(directory):
        for file in files:
            file_paths.append(os.path.join(root, file))
    return file_paths


def canonical_tar_name(name):
    while name.startswith("./"):
        name = name[2:]
    name = name.rstrip("/")
    assert not name.startswith("/"), f"Archive contains absolute path: {name}"
    parts = [part for part in name.split("/") if part not in ("", ".")]
    assert ".." not in parts, f"Archive contains path traversal: {name}"
    return "/".join(parts)


def archive_file_contents(path):
    result = {}
    with tarfile.open(path, "r:gz") as tar:
        for member in tar.getmembers():
            name = canonical_tar_name(member.name)
            if not name:
                assert member.isdir(), "Archive root entry is not a directory."
                continue
            if member.isdir():
                continue
            assert member.isfile() or member.islnk(), (
                f"Archive contains unsupported non-file member: {member.name}"
            )
            assert name not in result, f"Archive contains duplicate member path: {name}"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive member: {member.name}"
            result[name] = extracted.read()
    return result


def test_workspace_exists():
    assert os.path.exists(WORKSPACE_DIR), f"Workspace directory {WORKSPACE_DIR} does not exist."
    assert os.path.isdir(WORKSPACE_DIR), f"{WORKSPACE_DIR} is not a directory."


def test_incoming_archive_is_the_expected_source():
    assert os.path.exists(INCOMING_ARCHIVE), f"Incoming archive {INCOMING_ARCHIVE} is missing."
    assert archive_file_contents(INCOMING_ARCHIVE) == EXPECTED_INCOMING, (
        "Incoming archive no longer contains the expected original project files."
    )


def test_workspace_matches_decoded_source_exactly():
    actual_files = {}
    actual_dirs = set()

    for root, dirs, files in os.walk(WORKSPACE_DIR):
        for dirname in dirs:
            path = os.path.join(root, dirname)
            rel = os.path.relpath(path, WORKSPACE_DIR).replace(os.sep, "/")
            mode = os.lstat(path).st_mode
            assert stat.S_ISDIR(mode), f"Workspace entry is not a real directory: {rel}"
            actual_dirs.add(rel)

        for filename in files:
            path = os.path.join(root, filename)
            rel = os.path.relpath(path, WORKSPACE_DIR).replace(os.sep, "/")
            mode = os.lstat(path).st_mode
            assert stat.S_ISREG(mode), f"Workspace entry is not a regular file: {rel}"
            with open(path, "rb") as f:
                actual_files[rel] = f.read()

    assert actual_dirs == EXPECTED_DIRS, "Workspace directory layout does not match the source archive."
    assert actual_files == EXPECTED_WORKSPACE, (
        "Workspace files or contents do not match the source archive after ISO-8859-1 to UTF-8 conversion."
    )


def test_text_files_utf8_encoded():
    # Find all .txt files and ensure they can be read as UTF-8
    txt_files = [f for f in get_all_files(WORKSPACE_DIR) if f.endswith('.txt')]
    assert len(txt_files) > 0, "No .txt files found in the workspace."

    for txt_file in txt_files:
        try:
            with open(txt_file, 'r', encoding='utf-8') as f:
                content = f.read()
            assert content, f"Text file {txt_file} is empty."
        except UnicodeDecodeError:
            pytest.fail(f"File {txt_file} is not valid UTF-8.")


def test_hardlinks_created_for_duplicates():
    # The setup created identical CSV files.
    # docs/data_copy.csv, src/data.csv, src/data_backup.csv
    file1 = os.path.join(WORKSPACE_DIR, "docs/data_copy.csv")
    file2 = os.path.join(WORKSPACE_DIR, "src/data.csv")
    file3 = os.path.join(WORKSPACE_DIR, "src/data_backup.csv")

    assert os.path.exists(file1), f"{file1} is missing."
    assert os.path.exists(file2), f"{file2} is missing."
    assert os.path.exists(file3), f"{file3} is missing."

    stat1 = os.stat(file1)
    stat2 = os.stat(file2)
    stat3 = os.stat(file3)

    assert stat1.st_ino == stat2.st_ino, f"{file1} and {file2} are not hardlinked."
    assert stat1.st_ino == stat3.st_ino, f"{file1} and {file3} are not hardlinked."

    # Check that they have 3 hard links
    assert stat1.st_nlink >= 3, f"Expected at least 3 hardlinks for the duplicate files, got {stat1.st_nlink}."


def test_manifest_format_and_correctness():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist."

    with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, "Manifest file is empty."

    # Calculate expected hashes
    expected_entries = []
    for filepath in get_all_files(WORKSPACE_DIR):
        rel_path = "./" + os.path.relpath(filepath, WORKSPACE_DIR)
        with open(filepath, 'rb') as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()
        expected_entries.append(f"{file_hash}  {rel_path}")

    expected_entries.sort()

    # Ensure the manifest matches exactly
    assert lines == expected_entries, "Manifest contents do not match expected hashes, format, or sorting."


def test_clean_archive_structure():
    assert os.path.exists(CLEAN_ARCHIVE), f"Clean archive {CLEAN_ARCHIVE} does not exist."
    assert tarfile.is_tarfile(CLEAN_ARCHIVE), f"{CLEAN_ARCHIVE} is not a valid tar archive."

    with tarfile.open(CLEAN_ARCHIVE, 'r:gz') as tar:
        members = tar.getnames()

    assert len(members) > 0, "Clean archive is empty."

    for member in members:
        # The archive should not have a top-level project_workspace directory
        # Paths should be like 'docs/...', 'src/...', or './docs/...'
        parts = member.split('/')
        if parts[0] == '.':
            parts = parts[1:]
        if parts:
            assert parts[0] != "project_workspace", f"Archive contains top-level project_workspace directory: {member}"


def test_clean_archive_contains_exact_cleaned_workspace():
    archived_files = archive_file_contents(CLEAN_ARCHIVE)
    assert archived_files == EXPECTED_WORKSPACE, (
        "Clean archive does not contain exactly the cleaned workspace files and contents."
    )

    workspace_files = {}
    for path in get_all_files(WORKSPACE_DIR):
        rel = os.path.relpath(path, WORKSPACE_DIR).replace(os.sep, "/")
        with open(path, "rb") as f:
            workspace_files[rel] = f.read()
    assert archived_files == workspace_files, "Clean archive contents differ from the workspace."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
