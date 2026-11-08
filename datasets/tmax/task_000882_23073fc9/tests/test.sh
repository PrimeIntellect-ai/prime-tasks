#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import hashlib
import re
import pytest

INCOMING_DIR = "/home/user/incoming_logs"
MANIFEST_PATH = "/home/user/processed_manifest.txt"

def is_malicious(tar_path):
    """Check if the archive contains malicious paths."""
    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            for member in tar.getmembers():
                name = member.name
                if name.startswith("/") or name.startswith("../") or "/../" in name:
                    return True
    except tarfile.ReadError:
        pass
    return False

def calculate_disk_impact(tar_path):
    """Sum up Disk-Impact values within ERROR_START/ERROR_END blocks."""
    total = 0
    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            for member in tar.getmembers():
                if member.isfile():
                    f = tar.extractfile(member)
                    if f:
                        content = f.read().decode('utf-8', errors='ignore')
                        in_block = False
                        for line in content.splitlines():
                            if "ERROR_START" in line:
                                in_block = True
                            elif "ERROR_END" in line:
                                in_block = False
                            elif in_block and line.startswith("Disk-Impact:"):
                                parts = line.split(":")
                                if len(parts) == 2:
                                    try:
                                        total += int(parts[1].strip())
                                    except ValueError:
                                        pass
    except tarfile.ReadError:
        pass
    return total

def get_sha256(file_path):
    """Calculate SHA-256 checksum of a file."""
    sha256 = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()

def test_manifest_exists():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} was not created."

def test_manifest_content():
    assert os.path.isdir(INCOMING_DIR), f"Directory {INCOMING_DIR} is missing."

    safe_archives = []
    malicious_archives = []
    total_impact = 0

    for filename in os.listdir(INCOMING_DIR):
        if not filename.endswith(".tar.gz"):
            continue

        filepath = os.path.join(INCOMING_DIR, filename)
        if is_malicious(filepath):
            malicious_archives.append(filename)
        else:
            sha256 = get_sha256(filepath)
            safe_archives.append(f"{sha256} {filename}")
            total_impact += calculate_disk_impact(filepath)

    safe_archives.sort(key=lambda line: line.split(" ", 1)[1])
    malicious_archives.sort()

    expected_lines = ["SAFE_ARCHIVES:"]
    expected_lines.extend(safe_archives)
    expected_lines.append("")
    expected_lines.append("MALICIOUS_ARCHIVES:")
    expected_lines.extend(malicious_archives)
    expected_lines.append("")
    expected_lines.append(f"TOTAL_DISK_IMPACT: {total_impact}")

    expected_content = "\n".join(expected_lines).strip()

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Manifest content does not match expected.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
