#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import pytest

ASSETS_DIR = "/home/user/project_assets"
ORGANIZED_DIR = "/home/user/organized_binaries"
MANIFEST_FILE = "/home/user/manifest.txt"

EXPECTED_REGULAR_FILES = {
    "core_engine.bin": bytes.fromhex("7f454c46010101000000000000000000") + b"\ndata engine\n",
    "utils.so": bytes.fromhex("7f454c46020101000000000000000000") + b"\ndata utils\n",
    "fake.bin": bytes.fromhex("7f454c58010101000000000000000000") + b"\ndata fake\n",
    "readme.txt": b"just some text\n",
}

EXPECTED_SYMLINKS = {
    "sym_engine": "/home/user/project_assets/core_engine.bin",
    "sym_fake": "/home/user/project_assets/fake.bin",
}


def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def test_bad_symlinks_deleted():
    bad_links = ["loop1", "loop2", "self_loop", "broken_link"]
    for link in bad_links:
        path = os.path.join(ASSETS_DIR, link)
        assert not os.path.lexists(path), f"Bad symlink {path} was not deleted."


def test_original_assets_preserved():
    expected_names = set(EXPECTED_REGULAR_FILES) | set(EXPECTED_SYMLINKS)
    actual_names = set(os.listdir(ASSETS_DIR))
    assert actual_names == expected_names, (
        f"Original project assets were deleted, replaced, or augmented. "
        f"Expected: {expected_names}, Found: {actual_names}"
    )

    for name, expected_content in EXPECTED_REGULAR_FILES.items():
        path = os.path.join(ASSETS_DIR, name)
        assert os.path.isfile(path), f"Original file {path} is missing or not a file."
        assert not os.path.islink(path), f"Original file {path} was replaced by a symlink."
        with open(path, "rb") as f:
            actual_content = f.read()
        assert actual_content == expected_content, f"Original file {path} was modified or replaced."

    for name, expected_target in EXPECTED_SYMLINKS.items():
        path = os.path.join(ASSETS_DIR, name)
        assert os.path.islink(path), f"Original valid symlink {path} is missing or was replaced."
        assert os.readlink(path) == expected_target, f"Valid symlink {path} has the wrong target."


def test_organized_binaries_dir_exists():
    assert os.path.isdir(ORGANIZED_DIR), f"Directory {ORGANIZED_DIR} was not created."


def test_hardlinks_created_correctly():
    # Identify valid ELFs dynamically from ASSETS_DIR
    valid_elfs = {}
    for item in os.listdir(ASSETS_DIR):
        path = os.path.join(ASSETS_DIR, item)
        if os.path.isfile(path): # This resolves symlinks
            try:
                with open(path, "rb") as f:
                    header = f.read(4)
                if header == b"\x7fELF":
                    valid_elfs[item] = os.path.realpath(path)
            except Exception:
                pass

    assert len(valid_elfs) > 0, "No valid ELF files found in project_assets."

    organized_files = set(os.listdir(ORGANIZED_DIR))
    expected_files = set(valid_elfs.keys())

    assert organized_files == expected_files, f"Files in {ORGANIZED_DIR} do not match expected. Expected: {expected_files}, Found: {organized_files}"

    for item, target_path in valid_elfs.items():
        org_path = os.path.join(ORGANIZED_DIR, item)
        assert os.path.isfile(org_path), f"{org_path} is not a file."
        assert not os.path.islink(org_path), f"{org_path} should be a hard link, not a symlink."

        # Check if it's a hardlink to the target
        stat_org = os.stat(org_path)
        stat_target = os.stat(target_path)
        assert stat_org.st_dev == stat_target.st_dev and stat_org.st_ino == stat_target.st_ino, \
            f"{org_path} is not a hard link to {target_path}."


def test_manifest_file():
    assert os.path.isfile(MANIFEST_FILE), f"Manifest file {MANIFEST_FILE} does not exist."

    # Compute expected manifest
    expected_lines = []
    for item in os.listdir(ORGANIZED_DIR):
        path = os.path.join(ORGANIZED_DIR, item)
        if os.path.isfile(path) and not os.path.islink(path):
            file_hash = get_sha256(path)
            expected_lines.append(f"{file_hash}  {item}")

    expected_lines.sort()

    with open(MANIFEST_FILE, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "Manifest file contents do not match the expected sorted sha256sum output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
