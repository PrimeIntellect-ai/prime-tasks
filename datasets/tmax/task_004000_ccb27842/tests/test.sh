#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import io
import os
import posixpath
import stat
import tarfile

MANIFEST_PATH = "/home/user/change_manifest.txt"
ARCHIVE_PATH = "/home/user/update.tar.gz"
CURRENT_CONFIGS = "/home/user/current_configs"
LEGACY_EXTRACTED = "/home/user/legacy_extracted"
BACKUP_GLOB = "/home/user/backups/legacy_backup.tar.gz.*"


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def get_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def normalize_tar_name(name):
    assert not name.startswith("/"), f"Archive contains absolute path: {name}"
    normalized = posixpath.normpath(name)
    while normalized.startswith("./"):
        normalized = normalized[2:]
    assert normalized not in ("..", "") and not normalized.startswith("../"), (
        f"Archive contains unsafe path: {name}"
    )
    return normalized


def load_legacy_from_split_backup():
    parts = sorted(glob.glob(BACKUP_GLOB))
    expected_parts = [
        "/home/user/backups/legacy_backup.tar.gz.00",
        "/home/user/backups/legacy_backup.tar.gz.01",
        "/home/user/backups/legacy_backup.tar.gz.02",
    ]
    assert parts == expected_parts, f"Legacy backup parts are missing or unexpected: {parts}"

    combined = b""
    for part in parts:
        with open(part, "rb") as f:
            combined += f.read()

    with tarfile.open(fileobj=io.BytesIO(combined), mode="r:gz") as outer:
        inner_members = [
            m for m in outer.getmembers()
            if m.isfile() and normalize_tar_name(m.name) == "internal_configs.tar"
        ]
        assert len(inner_members) == 1, "Reassembled backup must contain internal_configs.tar"
        extracted = outer.extractfile(inner_members[0])
        assert extracted is not None, "Could not read internal_configs.tar"
        inner_data = extracted.read()

    files = {}
    directories = set()
    with tarfile.open(fileobj=io.BytesIO(inner_data), mode="r:") as inner:
        for member in inner.getmembers():
            name = normalize_tar_name(member.name)
            if name == ".":
                continue
            if member.isdir():
                directories.add(name.rstrip("/"))
            elif member.isfile():
                source = inner.extractfile(member)
                assert source is not None, f"Could not read legacy file {name}"
                assert name not in files, f"Duplicate legacy file path: {name}"
                files[name] = source.read()
            else:
                raise AssertionError(f"Unsupported entry in legacy archive: {member.name}")

    for name in files:
        parent = posixpath.dirname(name)
        while parent and parent != ".":
            directories.add(parent)
            parent = posixpath.dirname(parent)
    return files, directories


LEGACY_FILES, LEGACY_DIRS = load_legacy_from_split_backup()


def test_legacy_backup_was_fully_extracted_correctly():
    assert os.path.isdir(LEGACY_EXTRACTED), (
        f"Legacy extraction directory missing at {LEGACY_EXTRACTED}"
    )
    assert not os.path.islink(LEGACY_EXTRACTED), "legacy_extracted must be a real directory"

    actual_files = {}
    actual_dirs = set()
    for root, dirs, files in os.walk(LEGACY_EXTRACTED, followlinks=False):
        rel_root = os.path.relpath(root, LEGACY_EXTRACTED)
        if rel_root != ".":
            actual_dirs.add(rel_root.replace(os.sep, "/"))

        for dirname in dirs:
            path = os.path.join(root, dirname)
            assert not os.path.islink(path), f"Unexpected symlink in legacy extraction: {path}"

        for filename in files:
            path = os.path.join(root, filename)
            mode = os.lstat(path).st_mode
            assert stat.S_ISREG(mode), f"Unexpected non-regular legacy entry: {path}"
            rel = os.path.relpath(path, LEGACY_EXTRACTED).replace(os.sep, "/")
            with open(path, "rb") as f:
                actual_files[rel] = f.read()

    assert actual_dirs == LEGACY_DIRS, (
        f"Extracted legacy directories are incorrect. Expected {LEGACY_DIRS}, got {actual_dirs}"
    )
    assert actual_files == LEGACY_FILES, "Extracted legacy files do not match the split backup"


def derive_expected_changes():
    changes = {}
    for root, dirs, files in os.walk(CURRENT_CONFIGS, followlinks=True):
        for filename in files:
            if not filename.endswith(".conf"):
                continue
            absolute = os.path.join(root, filename)
            if not os.path.isfile(absolute):
                continue
            relative = os.path.relpath(absolute, CURRENT_CONFIGS).replace(os.sep, "/")
            with open(absolute, "rb") as f:
                current_data = f.read()
            if relative not in LEGACY_FILES:
                status = "NEW"
            elif sha256_bytes(current_data) != sha256_bytes(LEGACY_FILES[relative]):
                status = "MODIFIED"
            else:
                continue
            changes[relative] = (status, sha256_bytes(current_data))
    return changes


def test_manifest_exists_and_correct():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"

    expected_changes = derive_expected_changes()
    expected_lines = [
        f"[{expected_changes[path][0]}] ./{path} {expected_changes[path][1]}"
        for path in sorted(expected_changes)
    ]

    with open(MANIFEST_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Manifest contents are incorrect.\nExpected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_archive_exists_and_correct():
    assert os.path.exists(ARCHIVE_PATH), f"Update archive missing at {ARCHIVE_PATH}"
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"File {ARCHIVE_PATH} is not a valid tar archive"

    expected_members = set(derive_expected_changes())

    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()

        actual_file_list = [m.name.lstrip("./") for m in members if m.isfile()]
        actual_files = set(actual_file_list)
        assert actual_files == expected_members, (
            f"Archive contains incorrect files.\nExpected: {expected_members}\nActual: {actual_files}"
        )
        assert len(actual_file_list) == len(actual_files), "Archive contains duplicate file entries"

        symlinks = [m.name for m in members if m.issym() or m.islnk()]
        assert not symlinks, f"Archive must not contain symlinks, but found: {symlinks}"

        for member in members:
            if member.isfile():
                rel_name = member.name.lstrip("./")
                abs_path = os.path.join(CURRENT_CONFIGS, rel_name)
                archived = tar.extractfile(member)
                assert archived is not None, f"Could not read {member.name} from archive"
                archived_content = archived.read()
                with open(abs_path, "rb") as src:
                    expected_content = src.read()
                assert archived_content == expected_content, (
                    f"Content of {rel_name} in archive does not match {abs_path}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
