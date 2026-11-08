#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile
import json
import hashlib
import pytest

TAR_PATH = "/home/user/backups/financial_records_converted.tar.gz"

def test_tar_archive_exists():
    assert os.path.exists(TAR_PATH), f"Expected tar archive {TAR_PATH} does not exist."
    assert os.path.isfile(TAR_PATH), f"{TAR_PATH} is not a file."
    assert tarfile.is_tarfile(TAR_PATH), f"{TAR_PATH} is not a valid tar archive."

def test_tar_archive_contents():
    with tarfile.open(TAR_PATH, 'r:gz') as tar:
        names = tar.getnames()
        expected_files = {'file1.json', 'file2.json', 'file3.json', 'manifest.sha256'}
        assert set(names) == expected_files, f"Tar archive contents {set(names)} do not match expected {expected_files}."

def test_json_contents_in_tar():
    expected_data = {
        'file1.json': [
            {"id": "1", "name": "Alice", "amount": "100.50"},
            {"id": "2", "name": "Bob", "amount": "200.00"}
        ],
        'file2.json': [
            {"id": "3", "name": "Charlie", "amount": "300.75"}
        ],
        'file3.json': [
            {"id": "4", "name": "David", "amount": "50.25"}
        ]
    }

    with tarfile.open(TAR_PATH, 'r:gz') as tar:
        for fname, expected in expected_data.items():
            f = tar.extractfile(fname)
            assert f is not None, f"Could not extract {fname} from tar archive."
            data = json.load(f)
            assert data == expected, f"Content of {fname} does not match expected JSON."

def test_manifest_checksums_in_tar():
    with tarfile.open(TAR_PATH, 'r:gz') as tar:
        manifest_file = tar.extractfile('manifest.sha256')
        assert manifest_file is not None, "Could not extract manifest.sha256 from tar archive."
        manifest_content = manifest_file.read().decode('utf-8')

        for fname in ['file1.json', 'file2.json', 'file3.json']:
            f = tar.extractfile(fname)
            assert f is not None, f"Could not extract {fname} from tar archive."
            data = f.read()
            h = hashlib.sha256(data).hexdigest()
            expected_line = f"{h}  {fname}"
            assert expected_line in manifest_content, f"Manifest does not contain correct checksum line for {fname}. Expected: {expected_line}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
