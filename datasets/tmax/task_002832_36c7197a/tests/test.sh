#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import hashlib
import io
import os
import posixpath
import stat
import tarfile
import zipfile

import pytest

RAW_DIR = "/home/user/raw_dataset"
PROCESSING = "/home/user/processing"
EXTRACTED = "/home/user/extracted"
LOG_PATH = "/home/user/corrupted_archives.log"
FINAL_ARCHIVE = "/home/user/clean_dataset.tar.bz2"


def clean_name(name):
    name = name.replace("\\", "/")
    while name.startswith("./"):
        name = name[2:]
    name = posixpath.normpath(name)
    if name in ("", "."):
        return ""
    assert not name.startswith("/") and name != ".." and not name.startswith("../"), \
        f"Unsafe archive member path: {name}"
    return name.rstrip("/")


def add_parent_dirs(dirs, path):
    parent = posixpath.dirname(path)
    while parent and parent != ".":
        dirs.add(parent)
        parent = posixpath.dirname(parent)


def filesystem_tree(root):
    assert os.path.isdir(root), f"Required directory {root} does not exist"
    dirs, files, links = set(), {}, {}

    def visit(abs_dir, rel_dir=""):
        for entry in os.scandir(abs_dir):
            rel = posixpath.join(rel_dir, entry.name) if rel_dir else entry.name
            if entry.is_symlink():
                links[rel] = os.readlink(entry.path)
            elif entry.is_dir(follow_symlinks=False):
                dirs.add(rel)
                visit(entry.path, rel)
            elif entry.is_file(follow_symlinks=False):
                with open(entry.path, "rb") as f:
                    files[rel] = f.read()
            else:
                pytest.fail(f"Unexpected special file in {root}: {rel}")

    visit(root)
    return dirs, files, links


def load_source_model():
    parts = sorted(
        os.path.join(RAW_DIR, name)
        for name in os.listdir(RAW_DIR)
        if name.startswith("dataset.tar.gz.part")
    )
    assert parts, "No split dataset archive parts remain"
    assembled = b"".join(open(path, "rb").read() for path in parts)

    master_dirs, master_files, master_links = set(), {}, {}
    with tarfile.open(fileobj=io.BytesIO(assembled), mode="r:gz") as master:
        members = master.getmembers()
        assert members, "Reassembled master archive is empty"
        for member in members:
            name = clean_name(member.name)
            if not name:
                continue
            add_parent_dirs(master_dirs, name)
            if member.isdir():
                master_dirs.add(name)
            elif member.isfile():
                stream = master.extractfile(member)
                assert stream is not None
                master_files[name] = stream.read()
            elif member.issym():
                master_links[name] = member.linkname
            else:
                pytest.fail(f"Unsupported member in master archive: {member.name}")

    nested = {
        name: data for name, data in master_files.items()
        if name.lower().endswith(".zip") or name.lower().endswith(".tar.gz")
    }
    assert nested, "The master archive contains no nested archives"

    valid = {}
    corrupt = []
    for source_name, data in sorted(nested.items()):
        basename = posixpath.basename(source_name)
        lower = basename.lower()
        stem = basename[:-7] if lower.endswith(".tar.gz") else basename[:-4]
        files, dirs, links = {}, set(), {}
        try:
            if lower.endswith(".zip"):
                with zipfile.ZipFile(io.BytesIO(data), "r") as archive:
                    assert archive.testzip() is None
                    for member in archive.infolist():
                        name = clean_name(member.filename)
                        if not name:
                            continue
                        add_parent_dirs(dirs, name)
                        mode = member.external_attr >> 16
                        if member.is_dir():
                            dirs.add(name)
                        elif stat.S_ISLNK(mode):
                            links[name] = archive.read(member).decode("utf-8")
                        else:
                            files[name] = archive.read(member)
            else:
                with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
                    for member in archive.getmembers():
                        name = clean_name(member.name)
                        if not name:
                            continue
                        add_parent_dirs(dirs, name)
                        if member.isdir():
                            dirs.add(name)
                        elif member.isfile():
                            stream = archive.extractfile(member)
                            assert stream is not None
                            files[name] = stream.read()
                        elif member.issym():
                            links[name] = member.linkname
                        else:
                            pytest.fail(f"Unsupported nested member: {source_name}:{member.name}")
        except (AssertionError, EOFError, OSError, tarfile.TarError, zipfile.BadZipFile, RuntimeError, UnicodeError):
            corrupt.append(basename)
            continue

        valid[stem] = (files, dirs, links)

    return master_dirs, master_files, master_links, valid, corrupt


def expected_extracted_tree(valid):
    dirs, files, links = set(), {}, {}
    for stem, (archive_files, archive_dirs, archive_links) in valid.items():
        dirs.add(stem)
        for name, data in archive_files.items():
            path = posixpath.join(stem, name)
            files[path] = data
            add_parent_dirs(dirs, path)
        for name in archive_dirs:
            path = posixpath.join(stem, name)
            dirs.add(path)
            add_parent_dirs(dirs, path)

        nodes = set(archive_files) | set(archive_dirs) | set(archive_links)
        for name, target in archive_links.items():
            if target.startswith("/"):
                target_exists = os.path.exists(target)
            else:
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                target_exists = resolved in nodes
            if target_exists:
                path = posixpath.join(stem, name)
                links[path] = target
                add_parent_dirs(dirs, path)
    return dirs, files, links


def test_corrupted_archives_log():
    """Check that corrupted_archives.log contains exactly corrupt_data.zip"""
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert len(lines) == 1, f"Expected exactly 1 line in log, found {len(lines)}."
    assert lines[0] == "corrupt_data.zip", f"Expected 'corrupt_data.zip' in log, got '{lines[0]}'."


def test_extracted_data_contents():
    """Check that valid data was extracted correctly."""
    valid_data1_dir = "/home/user/extracted/valid_data1"
    valid_data2_dir = "/home/user/extracted/valid_data2"
    assert os.path.isdir(valid_data1_dir), f"{valid_data1_dir} does not exist."
    assert os.path.isdir(valid_data2_dir), f"{valid_data2_dir} does not exist."
    assert os.path.isfile(os.path.join(valid_data1_dir, "info.txt")), "valid_data1/info.txt missing"
    assert os.path.isfile(os.path.join(valid_data1_dir, "shared_measurements.txt")), "valid_data1/shared_measurements.txt missing"
    assert os.path.isfile(os.path.join(valid_data2_dir, "info.txt")), "valid_data2/info.txt missing"
    assert os.path.isfile(os.path.join(valid_data2_dir, "shared_measurements_copy.txt")), "valid_data2/shared_measurements_copy.txt missing"


def test_broken_link_removal():
    """Check that the broken symlink was removed."""
    path = "/home/user/extracted/valid_data2/broken_link.txt"
    assert not os.path.exists(path) and not os.path.islink(path), f"Broken link {path} should have been removed."


def test_hard_link_deduplication():
    """Check that identical files were hard-linked."""
    file1 = "/home/user/extracted/valid_data1/shared_measurements.txt"
    file2 = "/home/user/extracted/valid_data2/shared_measurements_copy.txt"
    assert os.path.isfile(file1), f"{file1} does not exist."
    assert os.path.isfile(file2), f"{file2} does not exist."
    assert os.stat(file1).st_ino == os.stat(file2).st_ino, "Deduplication failed."


def test_final_archive():
    """Check that the final archive exists, is a valid bz2 tarball, and preserves hard links."""
    assert os.path.isfile(FINAL_ARCHIVE), f"Final archive {FINAL_ARCHIVE} does not exist."
    try:
        with tarfile.open(FINAL_ARCHIVE, "r:bz2") as tar:
            members = tar.getmembers()
            assert any(m.islnk() for m in members), "No hard links found in the archive. Hard links were not preserved."
            basenames = [os.path.basename(m.name) for m in members]
            assert "info.txt" in basenames, "info.txt missing from final archive."
            assert "shared_measurements.txt" in basenames or "shared_measurements_copy.txt" in basenames, \
                "Shared measurements file missing from final archive."
    except tarfile.ReadError:
        pytest.fail(f"{FINAL_ARCHIVE} is not a valid bzip2 compressed tarball.")


def test_complete_pipeline_against_all_source_archives():
    master_dirs, master_files, master_links, valid, corrupt = load_source_model()

    actual_processing = filesystem_tree(PROCESSING)
    assert actual_processing == (master_dirs, master_files, master_links), \
        "processing/ is not an exact extraction of the reassembled split archive"

    assert os.path.isfile(LOG_PATH)
    with open(LOG_PATH) as f:
        logged = [line.strip() for line in f if line.strip()]
    assert collections.Counter(logged) == collections.Counter(corrupt), \
        "The corruption log does not account for every invalid nested archive"

    expected_dirs, expected_files, expected_links = expected_extracted_tree(valid)
    actual_dirs, actual_files, actual_links = filesystem_tree(EXTRACTED)
    assert actual_dirs == expected_dirs, "Extracted directory set is incomplete or contains fabricated extras"
    assert actual_files == expected_files, "Extracted file contents do not match all valid nested archives"
    assert actual_links == expected_links, "Broken links remain or valid links were not preserved"

    for corrupt_name in corrupt:
        lower = corrupt_name.lower()
        stem = corrupt_name[:-7] if lower.endswith(".tar.gz") else corrupt_name[:-4]
        assert not os.path.lexists(os.path.join(EXTRACTED, stem)), \
            f"Corrupt archive {corrupt_name} was extracted"

    by_digest = collections.defaultdict(list)
    for rel, data in actual_files.items():
        by_digest[hashlib.sha256(data).digest()].append(rel)
    for paths in by_digest.values():
        if len(paths) > 1:
            inode_keys = {(os.stat(os.path.join(EXTRACTED, p)).st_dev,
                           os.stat(os.path.join(EXTRACTED, p)).st_ino) for p in paths}
            assert len(inode_keys) == 1, f"Identical files are not all hard-linked: {paths}"

    assert os.path.isfile(FINAL_ARCHIVE)
    with tarfile.open(FINAL_ARCHIVE, "r:bz2") as archive:
        archived_dirs, archived_files, archived_links = set(), {}, {}
        member_by_path = {}
        hardlink_paths = set()

        for member in archive.getmembers():
            name = clean_name(member.name)
            if name == "extracted":
                continue
            if name.startswith("extracted/"):
                name = name[len("extracted/"):]
            if not name:
                continue
            assert name not in member_by_path, f"Duplicate path in final archive: {name}"
            member_by_path[name] = member
            if member.isdir():
                archived_dirs.add(name)
            elif member.isfile() or member.islnk():
                stream = archive.extractfile(member)
                assert stream is not None, f"Unreadable archive member: {name}"
                archived_files[name] = stream.read()
                if member.islnk():
                    hardlink_paths.add(name)
            elif member.issym():
                archived_links[name] = member.linkname
            else:
                pytest.fail(f"Unexpected special member in final archive: {name}")

        assert archived_dirs == actual_dirs, "Final archive does not contain the complete directory tree"
        assert archived_files == actual_files, "Final archive contents differ from extracted/"
        assert archived_links == actual_links, "Final archive link contents differ from extracted/"

        for paths in by_digest.values():
            if len(paths) > 1:
                assert len(set(paths) & hardlink_paths) >= len(paths) - 1, \
                    f"Final archive did not preserve hard links for {paths}"
        assert not any(path in hardlink_paths for paths in by_digest.values() if len(paths) == 1 for path in paths), \
            "Final archive contains a fabricated hard link unrelated to filesystem deduplication"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
