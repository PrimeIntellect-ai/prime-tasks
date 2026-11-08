#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import pytest

PROJECT_DIR = '/home/user/project'
ARCHIVE_DIR = '/home/user/archive'
LOG_PATH = os.path.join(PROJECT_DIR, 'deploy.log')
MANIFEST_PATH = os.path.join(ARCHIVE_DIR, 'manifest.json')

def get_deploy_records():
    if not os.path.exists(LOG_PATH):
        pytest.fail(f"Deployment log missing at {LOG_PATH}")

    records = []
    with open(LOG_PATH, 'r') as f:
        blocks = f.read().strip().split('\n\n')

    for block in blocks:
        if not block.strip():
            continue
        record = {}
        for line in block.split('\n'):
            line = line.strip()
            if line.startswith('Source:'):
                record['source'] = line.split(':', 1)[1].strip()
            elif line.startswith('Target:'):
                record['target'] = line.split(':', 1)[1].strip()
            elif line.startswith('Alias:'):
                record['alias'] = line.split(':', 1)[1].strip()
        if 'source' in record and 'target' in record:
            records.append(record)

    return records

def hash_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            h.update(chunk)
    return h.hexdigest()

@pytest.fixture(scope="module")
def records():
    return get_deploy_records()

def test_hard_links_created(records):
    assert records, "No records found in deploy log."
    for record in records:
        source_path = os.path.join(PROJECT_DIR, record['source'])
        target_path = os.path.join(ARCHIVE_DIR, record['target'])

        assert os.path.exists(source_path), f"Source file {source_path} is missing."
        assert os.path.exists(target_path), f"Target file {target_path} was not created."

        # Check hard link (same inode)
        source_stat = os.stat(source_path)
        target_stat = os.stat(target_path)
        assert source_stat.st_ino == target_stat.st_ino, \
            f"Target '{record['target']}' is not a hard link to '{record['source']}' (inode mismatch)."

def test_symlinks_created(records):
    assert records, "No records found in deploy log."
    for record in records:
        if 'alias' in record:
            alias_path = os.path.join(ARCHIVE_DIR, record['alias'])

            assert os.path.islink(alias_path), f"Alias '{record['alias']}' is not a symlink."

            # Check relative symlink target
            link_target = os.readlink(alias_path)
            assert link_target == record['target'], \
                f"Alias '{record['alias']}' symlink points to '{link_target}', expected '{record['target']}'."

def test_manifest_json_content(records):
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"

    with open(MANIFEST_PATH, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file at {MANIFEST_PATH} is not valid JSON.")

    assert 'manifest.json' not in manifest, "manifest.json should not be included in the manifest itself."

    expected_manifest = {}
    for record in records:
        source_path = os.path.join(PROJECT_DIR, record['source'])
        file_hash = hash_file(source_path)

        expected_manifest[record['target']] = file_hash
        if 'alias' in record:
            expected_manifest[record['alias']] = file_hash

    # Check that all expected keys are present and have the correct hash
    for key, expected_hash in expected_manifest.items():
        assert key in manifest, f"Key '{key}' is missing from manifest.json."
        assert manifest[key] == expected_hash, f"Hash mismatch for '{key}' in manifest.json."

    # Check for extra unexpected keys
    for key in manifest:
        assert key in expected_manifest, f"Unexpected key '{key}' found in manifest.json."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
