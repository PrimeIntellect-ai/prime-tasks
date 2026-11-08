#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import tarfile
import pytest

def test_finops_report_contents():
    report_path = '/home/user/finops_report.txt'
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_vms = ['alpha-testing', 'legacy-app-old']
    assert lines == expected_vms, f"Report contents are incorrect. Expected {expected_vms}, got {lines}"

def test_tarball_exists_and_contents():
    tarball_path = '/home/user/cold_storage/orphaned_disks_backup.tar.gz'
    assert os.path.isfile(tarball_path), f"Tarball {tarball_path} does not exist."

    assert tarfile.is_tarfile(tarball_path), f"File {tarball_path} is not a valid tar archive."

    with tarfile.open(tarball_path, 'r:gz') as tar:
        members = tar.getnames()

    # The archive should only contain the disk files, without directory structure
    expected_files = {'legacy_app_99.qcow2', 'test_env_alpha.qcow2'}

    # Check that only the expected files are in the tarball, with no extra paths
    actual_files = set(members)
    assert actual_files == expected_files, f"Tarball contents are incorrect. Expected {expected_files}, got {actual_files}"

def test_manifest_unmodified():
    manifest_path = '/home/user/vm_data/manifest.json'
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    with open(manifest_path, 'r') as f:
        data = json.load(f)

    assert len(data) == 5, "Manifest file seems to have been modified (incorrect number of entries)."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
