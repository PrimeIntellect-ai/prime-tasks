#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import subprocess
import tarfile
import tempfile

import pytest


def get_sha256(filepath):
    hasher = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def get_filtered_files():
    """Derive the required files from the Files sections of update.log."""
    log_path = "/home/user/update.log"
    assert os.path.isfile(log_path), f"Update log {log_path} is missing."

    listed_paths = []
    in_files_section = False
    with open(log_path, "r") as f:
        for line in f:
            stripped = line.strip()
            if stripped == "Files:":
                in_files_section = True
                continue
            if in_files_section:
                if stripped.startswith("/"):
                    listed_paths.append(stripped)
                else:
                    in_files_section = False

    base_dir = os.path.realpath("/home/user/etc")
    filtered = set()
    for filepath in listed_paths:
        if not os.path.isfile(filepath):
            continue
        try:
            if os.path.commonpath([base_dir, os.path.realpath(filepath)]) != base_dir:
                continue
        except ValueError:
            continue
        if os.path.getsize(filepath) >= 100 * 1024:
            continue
        if not filepath.endswith((".conf", ".yaml")):
            continue
        filtered.add(filepath)

    return sorted(filtered)


def expected_manifest_content(expected_files):
    return "".join(f"{get_sha256(filepath)}  {filepath}\n" for filepath in expected_files)


def test_manifest_correctness():
    """Verify the manifest is derived from update.log and has the required checksums."""
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    expected_files = get_filtered_files()
    expected_content = expected_manifest_content(expected_files)

    with open(manifest_path, "r") as f:
        actual_content = f.read()

    # Preserve the original normalized-content assertion.
    assert actual_content.strip() == expected_content.strip(), (
        f"Manifest content is incorrect. Expected:\n{expected_content}\nGot:\n{actual_content}"
    )


def test_backup_cpack_correctness():
    """Verify the cpack decodes to a gzip tar with exactly the required absolute members."""
    cpack_path = "/home/user/backup.cpack"
    assert os.path.isfile(cpack_path), f"Backup file {cpack_path} is missing."

    expected_files = get_filtered_files()
    expected_members = expected_files + ["/home/user/manifest.txt"]

    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with open(cpack_path, "rb") as f:
                encoded_data = b"".join(f.read().split())
            compressed_data = base64.b64decode(encoded_data, validate=True)
        except Exception as e:
            pytest.fail(f"Failed to base64 decode {cpack_path}: {e}")

        tar_gz_path = os.path.join(tmpdir, "backup.tar.gz")
        with open(tar_gz_path, "wb") as f:
            f.write(compressed_data)

        try:
            with tarfile.open(tar_gz_path, "r:gz") as archive:
                members = archive.getmembers()
        except Exception as e:
            pytest.fail(f"Decoded data is not a valid gzip-compressed tar archive: {e}")

        member_names = [member.name for member in members]
        assert len(member_names) == len(expected_members), (
            f"Archive has extra, missing, or duplicate members. "
            f"Expected {expected_members}, got {member_names}"
        )
        assert sorted(member_names) == sorted(expected_members), (
            f"Archive members are incorrect. Expected exactly the absolute paths "
            f"{expected_members}, got {member_names}"
        )
        assert all(name.startswith("/") for name in member_names), (
            f"All archive member names must be absolute: {member_names}"
        )
        assert all(member.isfile() for member in members), (
            "Every archive member must be a regular file."
        )

        # Preserve the original extraction assertion.
        try:
            subprocess.run(
                ["tar", "-xzf", tar_gz_path, "-C", tmpdir],
                check=True,
                capture_output=True,
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Failed to extract tar archive from decoded data: {e.stderr.decode()}")

        for absolute_path in expected_members:
            rel_path = absolute_path.lstrip("/")
            extracted_path = os.path.join(tmpdir, rel_path)
            assert os.path.isfile(extracted_path), (
                f"Expected file {rel_path} is missing from the extracted archive."
            )
            assert get_sha256(extracted_path) == get_sha256(absolute_path), (
                f"Content of extracted file {rel_path} does not match the original."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
