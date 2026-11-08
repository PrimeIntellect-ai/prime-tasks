#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import gzip
import json
import pytest

def test_curated_directories_and_symlinks():
    """Verify that the curated directories and symlinks are correctly created."""
    raw_dir = '/home/user/raw_artifacts'
    curated_dir = '/home/user/curated'

    assert os.path.isdir(raw_dir), f"{raw_dir} is missing."
    assert os.path.isdir(curated_dir), f"{curated_dir} is missing."

    files = [f for f in os.listdir(raw_dir) if f.endswith('.bin.gz')]
    assert len(files) == 20, f"Expected 20 .bin.gz files in {raw_dir}, found {len(files)}."

    for filename in files:
        raw_path = os.path.join(raw_dir, filename)

        # Determine the true architecture
        with gzip.open(raw_path, 'rb') as f:
            arch_bytes = f.read(8)
            arch = arch_bytes.decode('ascii')

        assert arch in ["ARCH_X86", "ARCH_ARM"], f"Unknown architecture {arch} in {filename}."

        arch_dir = os.path.join(curated_dir, arch)
        assert os.path.isdir(arch_dir), f"Directory {arch_dir} was not created for {filename}."

        symlink_path = os.path.join(arch_dir, filename)
        assert os.path.islink(symlink_path), f"File {symlink_path} is not a symbolic link."

        target = os.readlink(symlink_path)
        assert target == raw_path, f"Symlink {symlink_path} points to {target}, expected {raw_path}."

def test_manifest_updated():
    """Verify that the manifest has been correctly updated."""
    source_manifest_path = '/home/user/metadata/manifest.txt'
    updated_manifest_path = '/home/user/metadata/manifest_updated.txt'
    assert os.path.isfile(updated_manifest_path), f"{updated_manifest_path} is missing."

    with open(updated_manifest_path, 'r') as f:
        lines = f.readlines()

    assert len(lines) == 50000, f"Expected 50000 lines in updated manifest, found {len(lines)}."

    deprecated_count = sum(1 for line in lines if 'SERVER_A_DEPRECATED' in line)
    assert deprecated_count == 0, f"Found {deprecated_count} instances of SERVER_A_DEPRECATED in updated manifest; expected 0."

    active_count = sum(1 for line in lines if 'SERVER_B_ACTIVE' in line)
    assert active_count == 5000, f"Expected 5000 occurrences of SERVER_B_ACTIVE, found {active_count}."

    # Require the output to be exactly the source manifest with only the requested
    # byte-string replacement, preserving every other byte and line.
    with open(source_manifest_path, 'rb') as f:
        source_content = f.read()
    with open(updated_manifest_path, 'rb') as f:
        updated_content = f.read()
    expected_content = source_content.replace(b'SERVER_A_DEPRECATED', b'SERVER_B_ACTIVE')
    assert updated_content == expected_content, (
        'manifest_updated.txt is not an exact replacement of '
        'SERVER_A_DEPRECATED with SERVER_B_ACTIVE in manifest.txt.'
    )

def test_report_json():
    """Verify that the JSON report contains the correct mappings."""
    report_path = '/home/user/report.json'
    assert os.path.isfile(report_path), f"{report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON from {report_path}: {e}")

    raw_dir = '/home/user/raw_artifacts'
    files = [f for f in os.listdir(raw_dir) if f.endswith('.bin.gz')]

    assert len(report_data) == 20, f"Expected 20 entries in report.json, found {len(report_data)}."

    for filename in files:
        assert filename in report_data, f"{filename} is missing from report.json."

        raw_path = os.path.join(raw_dir, filename)
        with gzip.open(raw_path, 'rb') as f:
            expected_arch = f.read(8).decode('ascii')

        actual_arch = report_data[filename]
        assert actual_arch == expected_arch, f"Expected architecture {expected_arch} for {filename}, but report.json has {actual_arch}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
