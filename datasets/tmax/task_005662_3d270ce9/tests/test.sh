#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import tarfile
import pytest

ARCHIVE_PATH = "/home/user/backup/docs_diff.tar.gz"
REPO_PATH = "/home/user/doc_repo"
CHECKSUM_PATH = "/home/user/backup/full_checksums.txt"
EXPECTED_FILES = {"doc_015.txt", "doc_042.txt", "doc_088.txt", "doc_101.txt", "doc_102.txt"}


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def recorded_checksums():
    result = {}
    with open(CHECKSUM_PATH, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            checksum, marker_and_name = line.split(" ", 1)
            name = marker_and_name.lstrip(" *")
            result[os.path.normpath(name)] = checksum
    return result


def derive_expected_files():
    recorded = recorded_checksums()
    expected = {}
    for root, dirs, files in os.walk(REPO_PATH):
        dirs.sort()
        files.sort()
        for filename in files:
            source = os.path.join(root, filename)
            if not os.path.isfile(source) or os.path.islink(source):
                continue
            relative = os.path.normpath(os.path.relpath(source, REPO_PATH))
            if relative not in recorded or sha256_file(source) != recorded[relative]:
                expected[relative] = source
    return expected


def member_relative_name(name):
    normalized = os.path.normpath(name)
    repo_normalized = os.path.normpath(REPO_PATH)
    repo_without_leading_slash = repo_normalized.lstrip(os.sep)

    if normalized.startswith(repo_normalized + os.sep):
        return os.path.relpath(normalized, repo_normalized)
    if normalized.startswith(repo_without_leading_slash + os.sep):
        return os.path.relpath(normalized, repo_without_leading_slash)
    if not os.path.isabs(normalized) and normalized != ".." and not normalized.startswith(".." + os.sep):
        return normalized[2:] if normalized.startswith("." + os.sep) else normalized
    return None


def test_archive_exists():
    """Verify that the differential backup archive exists."""
    assert os.path.isfile(ARCHIVE_PATH), f"Archive not found at {ARCHIVE_PATH}"


def test_archive_is_valid_tar_gz():
    """Verify that the archive is a valid gzipped tarball."""
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"File {ARCHIVE_PATH} is not a valid tar archive."
    try:
        with tarfile.open(ARCHIVE_PATH, "r:gz"):
            pass
    except Exception as e:
        pytest.fail(f"Could not open archive as a gzip-compressed tarball: {e}")


def test_archive_contents():
    """Verify names, member types, and bytes against the repository and checksum manifest."""
    expected = derive_expected_files()

    try:
        with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
            members = tar.getmembers()

            # Preserve the original basename assertion.
            actual_files = set()
            for member in members:
                if member.isfile():
                    basename = os.path.basename(member.name)
                    if basename.endswith(".txt"):
                        actual_files.add(basename)
            assert actual_files == EXPECTED_FILES, (
                "Archive contents do not match expected files.\n"
                f"Expected: {sorted(EXPECTED_FILES)}\n"
                f"Found: {sorted(actual_files)}"
            )

            assert set(expected) == EXPECTED_FILES, (
                f"Derived changed/new files differ from fixture expectation: {sorted(expected)}"
            )
            assert all(member.isfile() for member in members), (
                "Archive contains a directory, link, device, or other non-regular member"
            )
            assert len(members) == len(expected), (
                "Archive must contain exactly one regular member per changed/new file"
            )

            seen = set()
            for member in members:
                relative = member_relative_name(member.name)
                assert relative in expected, f"Unexpected archive member: {member.name!r}"
                assert relative not in seen, f"Duplicate archive member for {relative!r}"
                seen.add(relative)

                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read archive member {member.name!r}"
                archived_bytes = extracted.read()
                with open(expected[relative], "rb") as source:
                    source_bytes = source.read()
                assert archived_bytes == source_bytes, (
                    f"Archived content for {relative!r} does not match the current repository file"
                )

            assert seen == set(expected), (
                f"Archive members differ from derived changed/new files: {sorted(seen)}"
            )
    except (tarfile.TarError, OSError) as e:
        pytest.fail(f"Failed to read archive contents: {e}")


def test_no_intermediate_uncompressed_tar_left_in_backup_directory():
    """Ensure no residual uncompressed tar artifact was left beside the streamed output."""
    for entry in os.scandir("/home/user/backup"):
        if not entry.is_file(follow_symlinks=False) or entry.path == ARCHIVE_PATH:
            continue
        if not tarfile.is_tarfile(entry.path):
            continue
        with open(entry.path, "rb") as handle:
            assert handle.read(2) == b"\x1f\x8b", (
                f"Residual uncompressed tar archive found: {entry.path}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
