#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import pytest

ARCHIVE_DIR = "/home/user/archive"
TAR_PATH = os.path.join(ARCHIVE_DIR, "safe_backup.tar")
MANIFEST_PATH = os.path.join(ARCHIVE_DIR, "manifest.txt")

EXPECTED_FILES_AND_SIZES = {
    "part1.gcode": 45,
    "part2.gcode": 24,
    "log1.wal": 8,
    "log2.wal": 16,
}

EXPECTED_MANIFEST_LINES = [
    "/home/user/machine_data/folder_A/folder_B/log2.wal,16",
    "/home/user/machine_data/folder_A/part2.gcode,24",
    "/home/user/machine_data/folder_C/log1.wal,8",
    "/home/user/machine_data/part1.gcode,45"
]

def expected_gcode(filename):
    source_by_name = {
        "part1.gcode": "/home/user/machine_data/part1.gcode",
        "part2.gcode": "/home/user/machine_data/folder_A/part2.gcode",
    }
    with open(source_by_name[filename], "rb") as f:
        source = f.read()
    return source.decode("shift_jis").encode("utf-8")

def test_archive_directory_exists():
    assert os.path.isdir(ARCHIVE_DIR), f"Archive directory {ARCHIVE_DIR} does not exist."

def test_tar_file_exists_and_valid():
    assert os.path.isfile(TAR_PATH), f"Tar file {TAR_PATH} is missing."
    assert tarfile.is_tarfile(TAR_PATH), f"{TAR_PATH} is not a valid tar archive."

def test_tar_file_contents():
    with tarfile.open(TAR_PATH, "r") as tar:
        members = tar.getmembers()

        # Check flat structure
        for member in members:
            assert "/" not in member.name, f"File {member.name} in tarball is not at the root (flat structure required)."

        names = {m.name for m in members}
        assert names == set(EXPECTED_FILES_AND_SIZES.keys()), f"Tarball contains incorrect files. Expected {set(EXPECTED_FILES_AND_SIZES.keys())}, found {names}."

        for member in members:
            expected_size = EXPECTED_FILES_AND_SIZES[member.name]
            assert member.size == expected_size, f"File {member.name} in tarball has incorrect size. Expected {expected_size}, got {member.size}."

def test_gcode_utf8_conversion():
    with tarfile.open(TAR_PATH, "r") as tar:
        for filename in ["part1.gcode", "part2.gcode"]:
            f = tar.extractfile(filename)
            assert f is not None, f"Could not extract {filename} from tarball."
            content = f.read()
            try:
                decoded = content.decode("utf-8")
            except UnicodeDecodeError:
                pytest.fail(f"File {filename} in tarball is not valid UTF-8.")

            # Retain the original expected-text checks.
            if filename == "part1.gcode":
                assert "テスト" in decoded and "終了" in decoded, f"Expected Japanese text missing in {filename}."
            elif filename == "part2.gcode":
                assert "安全位置" in decoded, f"Expected Japanese text missing in {filename}."

            # Verify the complete conversion rather than only selected substrings.
            expected = expected_gcode(filename)
            assert content == expected, (
                f"{filename} does not exactly preserve the source GCode after "
                f"Shift-JIS to UTF-8 conversion."
            )

def test_wal_rle_conversion():
    with tarfile.open(TAR_PATH, "r") as tar:
        # Check log1.wal
        f1 = tar.extractfile("log1.wal")
        assert f1 is not None, "Could not extract log1.wal from tarball."
        log1_data = f1.read()
        expected_log1 = bytes([5, 0x00, 255, 0xFF, 45, 0xFF, 2, 0x01])
        assert log1_data == expected_log1, f"log1.wal RLE encoding is incorrect. Expected {expected_log1.hex()}, got {log1_data.hex()}."

        # Check log2.wal
        f2 = tar.extractfile("log2.wal")
        assert f2 is not None, "Could not extract log2.wal from tarball."
        log2_data = f2.read()
        expected_log2 = bytes([
            1, 0x10, 1, 0x20, 1, 0x30, 1, 0x40,
            1, 0x10, 1, 0x20, 1, 0x30, 1, 0x40
        ])
        assert log2_data == expected_log2, f"log2.wal RLE encoding is incorrect. Expected {expected_log2.hex()}, got {log2_data.hex()}."

def test_manifest_exists_and_correct():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_MANIFEST_LINES, (
        f"Manifest contents are incorrect or incorrectly sorted.\n"
        f"Expected:\n{EXPECTED_MANIFEST_LINES}\nGot:\n{lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
