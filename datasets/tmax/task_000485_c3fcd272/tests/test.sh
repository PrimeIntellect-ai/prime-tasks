#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import runpy
import shutil
import struct
import sys
import pytest

SCRIPT_PATH = "/home/user/organize.py"
RAW_DIR = "/home/user/raw_dataset"
ORGANIZED_DIR = "/home/user/organized_dataset"


def test_script_exists_executes_and_uses_mmap():
    assert os.path.exists(SCRIPT_PATH), f"Required script does not exist: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Required script is not a regular file: {SCRIPT_PATH}"

    assert os.path.isdir(RAW_DIR), f"Directory {RAW_DIR} does not exist."
    raw_paths = {
        os.path.realpath(os.path.join(RAW_DIR, name))
        for name in os.listdir(RAW_DIR)
        if name.endswith('.dat')
    }
    assert raw_paths, f"No .dat files found in {RAW_DIR}."

    # Remove any pre-created results so the submitted script must produce them.
    if os.path.lexists(ORGANIZED_DIR):
        if os.path.islink(ORGANIZED_DIR) or not os.path.isdir(ORGANIZED_DIR):
            os.unlink(ORGANIZED_DIR)
        else:
            shutil.rmtree(ORGANIZED_DIR)
    os.makedirs(ORGANIZED_DIR)

    mmap_paths = set()

    def audit_hook(event, args):
        if event != "mmap.__new__":
            return
        try:
            fd = args[0]
            mapped_path = os.path.realpath(os.readlink(f"/proc/self/fd/{fd}"))
            if mapped_path in raw_paths:
                mmap_paths.add(mapped_path)
        except (IndexError, TypeError, ValueError, OSError):
            pass

    sys.addaudithook(audit_hook)
    old_argv = sys.argv
    try:
        sys.argv = [SCRIPT_PATH]
        runpy.run_path(SCRIPT_PATH, run_name="__main__")
    finally:
        sys.argv = old_argv

    missing_mmaps = raw_paths - mmap_paths
    assert not missing_mmaps, (
        "The script did not use Python mmap on every .dat file: "
        + ", ".join(sorted(missing_mmaps))
    )


def test_organized_dataset_symlinks():
    raw_dir = "/home/user/raw_dataset"
    organized_dir = "/home/user/organized_dataset"

    assert os.path.isdir(raw_dir), f"Directory {raw_dir} does not exist."
    assert os.path.isdir(organized_dir), f"Directory {organized_dir} does not exist."

    # Find all .dat files in the raw dataset
    raw_files = [f for f in os.listdir(raw_dir) if f.endswith('.dat')]
    assert len(raw_files) > 0, f"No .dat files found in {raw_dir}."

    expected_symlinks = {}

    for raw_file in raw_files:
        raw_path = os.path.join(raw_dir, raw_file)

        # Read the header to determine expected symlink location
        with open(raw_path, "rb") as f:
            header = f.read(24)

        assert len(header) == 24, f"File {raw_path} is smaller than 24 bytes."

        magic = header[0:8]
        if magic != b"SNSR_DAT":
            continue # Skip files that don't match the magic string if any

        sensor_id_raw = header[8:16]
        sensor_id = sensor_id_raw.replace(b'\x00', b'').decode('ascii')

        timestamp = struct.unpack("<Q", header[16:24])[0]

        expected_symlink_path = os.path.join(organized_dir, sensor_id, f"{timestamp}.dat")
        expected_symlinks[expected_symlink_path] = raw_path

    assert len(expected_symlinks) > 0, "No valid sensor data files were found to verify."

    # Verify each expected symlink
    for symlink_path, target_path in expected_symlinks.items():
        assert os.path.exists(symlink_path), f"Expected symlink is missing: {symlink_path}"
        assert os.path.islink(symlink_path), f"Path exists but is not a symlink: {symlink_path}"

        actual_target = os.readlink(symlink_path)
        assert actual_target == target_path, (
            f"Symlink {symlink_path} points to {actual_target}, "
            f"but should point to {target_path}"
        )

    # Verify no unexpected files exist in the organized directory
    actual_symlinks_found = 0
    for root, dirs, files in os.walk(organized_dir):
        for file in files:
            file_path = os.path.join(root, file)
            assert file_path in expected_symlinks, f"Unexpected file found in organized dataset: {file_path}"
            actual_symlinks_found += 1

    assert actual_symlinks_found == len(expected_symlinks), (
        f"Expected {len(expected_symlinks)} symlinks, but found {actual_symlinks_found}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
