#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib
import pytest

ORGANIZED_DIR = "/home/user/organized"
REPORT_FILE = "/home/user/organization_report.log"

EXPECTED_FILES = {
    "images/png/asset_A": b"\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x01",
    "images/png/asset_C": b"\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x01",
    "binaries/elf/asset_B": b"\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00",
    "binaries/elf/asset_E": b"\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x01",
    "unknown/asset_D": b"\x11\x22\x33\x44\x55\x66\x77",
    "unknown/asset_G": b"\x11\x22\x33\x44\x55\x66\x77",
    "images/jpeg/asset_F": b"\xff\xd8\xff\xe0\x00\x10\x4a\x46\x49\x46\x00\x01",
}

def test_categorization_and_content():
    """Verify that files are in the correct directories with correct content."""
    for rel_path, expected_content in EXPECTED_FILES.items():
        full_path = os.path.join(ORGANIZED_DIR, rel_path)
        assert os.path.isfile(full_path), f"Expected file missing: {full_path}"

        with open(full_path, "rb") as f:
            content = f.read()
        assert content == expected_content, f"Content mismatch in {full_path}"

def test_hard_link_deduplication():
    """Verify that identical files share the same inode (hard links)."""
    # asset_A and asset_C
    path_a = os.path.join(ORGANIZED_DIR, "images/png/asset_A")
    path_c = os.path.join(ORGANIZED_DIR, "images/png/asset_C")
    assert os.path.exists(path_a) and os.path.exists(path_c), "asset_A or asset_C missing"

    stat_a = os.stat(path_a)
    stat_c = os.stat(path_c)
    assert stat_a.st_ino == stat_c.st_ino, "asset_A and asset_C do not share the same inode (not hard linked)"
    assert stat_a.st_nlink >= 2, "asset_A does not have multiple hard links"

    # asset_D and asset_G
    path_d = os.path.join(ORGANIZED_DIR, "unknown/asset_D")
    path_g = os.path.join(ORGANIZED_DIR, "unknown/asset_G")
    assert os.path.exists(path_d) and os.path.exists(path_g), "asset_D or asset_G missing"

    stat_d = os.stat(path_d)
    stat_g = os.stat(path_g)
    assert stat_d.st_ino == stat_g.st_ino, "asset_D and asset_G do not share the same inode (not hard linked)"
    assert stat_d.st_nlink >= 2, "asset_D does not have multiple hard links"

def test_report_generation():
    """Verify the organization report is correct, hashed, and sorted."""
    assert os.path.isfile(REPORT_FILE), f"Report file missing: {REPORT_FILE}"

    expected_lines = []
    for rel_path, content in EXPECTED_FILES.items():
        sha256 = hashlib.sha256(content).hexdigest()
        expected_lines.append(f"{sha256} {rel_path}")

    expected_lines.sort()

    with open(REPORT_FILE, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "Report content or sorting is incorrect"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
