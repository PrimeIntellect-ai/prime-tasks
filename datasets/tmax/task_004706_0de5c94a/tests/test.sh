#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import tarfile


def compute_sha256(file_path):
    sha256 = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def compute_stream_sha256(stream):
    sha256 = hashlib.sha256()
    for chunk in iter(lambda: stream.read(4096), b""):
        sha256.update(chunk)
    return sha256.hexdigest()


def clean_member_name(name):
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def test_manifest_v2_generated_correctly():
    manifest_path = "/home/user/backups/manifest_v2.json"
    assert os.path.isfile(manifest_path), f"Manifest file missing: {manifest_path}"

    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Manifest file {manifest_path} is not valid JSON."

    repo_dir = "/home/user/repo"
    expected_files = [
        "bin/app_v1",
        "bin/app_v2",
        "lib/libcore.so",
        "lib/libold.so"
    ]

    unexpected_files = [
        "bin/cache.tmp",
        "docs/readme.txt"
    ]

    for f in expected_files:
        assert f in manifest, f"Expected file {f} missing from manifest_v2.json"
        actual_path = os.path.join(repo_dir, f)
        expected_hash = compute_sha256(actual_path)
        assert manifest[f] == expected_hash, f"Hash mismatch for {f} in manifest_v2.json"

    for f in unexpected_files:
        assert f not in manifest, f"File {f} should not be included in manifest_v2.json (check include_dirs and exclude_patterns)"

    # Ensure no extra files are present
    for f in manifest.keys():
        assert f in expected_files, f"Unexpected file {f} found in manifest_v2.json"


def test_backup_summary_generated_correctly():
    summary_path = "/home/user/backups/backup_summary.txt"
    assert os.path.isfile(summary_path), f"Summary file missing: {summary_path}"

    with open(summary_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "MODIFIED: lib/libcore.so",
        "NEW: bin/app_v2"
    ]

    # The prompt requires them to be sorted alphabetically by file path.
    # "bin/app_v2" comes before "lib/libcore.so"
    expected_sorted = [
        "NEW: bin/app_v2",
        "MODIFIED: lib/libcore.so"
    ]

    assert lines == expected_sorted, f"Backup summary content or sorting is incorrect. Expected {expected_sorted}, got {lines}"


def test_incremental_tarball_generated_correctly():
    tarball_path = "/home/user/backups/incremental_v2.tar.gz"
    assert os.path.isfile(tarball_path), f"Tarball file missing: {tarball_path}"

    assert tarfile.is_tarfile(tarball_path), f"File {tarball_path} is not a valid tar archive"

    expected_files = {
        "bin/app_v2",
        "lib/libcore.so"
    }

    unexpected_files = {
        "bin/app_v1",
        "lib/libold.so",
        "bin/cache.tmp",
        "docs/readme.txt"
    }

    with tarfile.open(tarball_path, 'r:gz') as tar:
        members = tar.getnames()
        member_objects = tar.getmembers()

        # Clean up member names (sometimes they might have a leading ./)
        cleaned_members = {m.lstrip('./') for m in members}

        for f in expected_files:
            assert f in cleaned_members, f"Expected file {f} missing from {tarball_path}"

        for f in unexpected_files:
            assert f not in cleaned_members, f"Unexpected file {f} found in {tarball_path}"

        # Ensure no absolute paths
        for m in members:
            assert not m.startswith("/"), f"Tarball contains absolute path: {m}. Paths must be relative to /home/user/repo/"
            assert not m.startswith("home/user/repo"), f"Tarball contains full path structure: {m}. Paths must be relative to /home/user/repo/"

        # Only the two required regular files may be archived. Parent directory
        # entries are harmless and are permitted, but all other member types and
        # names are rejected.
        file_members = []
        seen_file_names = set()
        allowed_directories = {"bin", "lib"}

        for member in member_objects:
            name = clean_member_name(member.name)
            assert name and name != ".", f"Unexpected archive member: {member.name}"
            assert ".." not in name.split("/"), f"Tarball contains path traversal: {member.name}"

            if member.isfile():
                assert name in expected_files, f"Unexpected file {name} found in {tarball_path}"
                assert name not in seen_file_names, f"Duplicate file entry {name} found in {tarball_path}"
                seen_file_names.add(name)
                file_members.append((name, member))
            else:
                assert member.isdir(), f"Unexpected non-file archive member: {member.name}"
                assert name in allowed_directories, f"Unexpected directory entry {member.name} found in {tarball_path}"

        assert seen_file_names == expected_files, \
            f"Tarball must contain exactly {sorted(expected_files)}, got {sorted(seen_file_names)}"
        assert len(file_members) == len(expected_files), "Tarball contains duplicate or extra file entries"

        # Verify that each archived file contains the actual repository bytes,
        # rather than merely having the required member name.
        for name, member in file_members:
            archived_file = tar.extractfile(member)
            assert archived_file is not None, f"Could not read archived file {name}"
            with archived_file:
                archived_hash = compute_stream_sha256(archived_file)
            repository_hash = compute_sha256(os.path.join("/home/user/repo", name))
            assert archived_hash == repository_hash, \
                f"Archived bytes for {name} do not match the repository file"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
