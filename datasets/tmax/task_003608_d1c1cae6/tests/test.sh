#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import tarfile
import pytest

def test_tarball_exists():
    tar_path = '/home/user/incremental_backup.tar.gz'
    assert os.path.isfile(tar_path), f"Archive {tar_path} is missing."

def test_tarball_contents():
    tar_path = '/home/user/incremental_backup.tar.gz'
    expected_files = {'new_data.json', 'new_config.json', 'new_settings.json'}

    with tarfile.open(tar_path, 'r:gz') as tar:
        members = tar.getmembers()

        # Check that there are no directories
        for member in members:
            assert member.isfile(), f"Archive contains a non-file member: {member.name}"
            # Check that files are at the root
            assert '/' not in member.name, f"Archive contains nested file: {member.name}"

        file_names = {member.name for member in members}
        assert file_names == expected_files, f"Archive contents do not match. Expected {expected_files}, got {file_names}"

def test_tarball_extracted_json_contents():
    tar_path = '/home/user/incremental_backup.tar.gz'

    expected_data = {
        'new_data.json': [{"id": "3", "name": "gamma", "value": "300"}],
        'new_config.json': [{"id": "4", "name": "delta", "value": "400"}],
        'new_settings.json': [{"id": "5", "name": "epsilon", "value": "500"}]
    }

    with tarfile.open(tar_path, 'r:gz') as tar:
        for file_name, expected_json in expected_data.items():
            member = tar.getmember(file_name)
            f = tar.extractfile(member)
            assert f is not None, f"Could not extract {file_name} from archive."

            content = f.read().decode('utf-8')
            try:
                parsed_json = json.loads(content)
            except json.JSONDecodeError:
                pytest.fail(f"File {file_name} in archive is not valid JSON.")

            assert parsed_json == expected_json, f"Content of {file_name} does not match expected JSON. Got {parsed_json}"

def test_staging_contents():
    staging_path = '/home/user/backup_staging'
    expected_data = {
        'new_data.json': [{"id": "3", "name": "gamma", "value": "300"}],
        'new_config.json': [{"id": "4", "name": "delta", "value": "400"}],
        'new_settings.json': [{"id": "5", "name": "epsilon", "value": "500"}]
    }

    assert os.path.isdir(staging_path), f"Staging directory {staging_path} is missing."
    staged_json_files = {
        name for name in os.listdir(staging_path)
        if name.endswith('.json')
    }
    assert staged_json_files == set(expected_data), (
        f"Staged JSON files do not match. Expected {set(expected_data)}, got {staged_json_files}"
    )

    for file_name, expected_json in expected_data.items():
        staged_file = os.path.join(staging_path, file_name)
        assert os.path.isfile(staged_file), f"Staged file {staged_file} is missing."
        try:
            with open(staged_file, 'r') as f:
                parsed_json = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Staged file {staged_file} is not valid JSON.")
        assert parsed_json == expected_json, (
            f"Content of staged file {file_name} does not match expected JSON. Got {parsed_json}"
        )

def test_manifest_file():
    manifest_path = '/home/user/backup_manifest.json'
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    with open(manifest_path, 'r') as f:
        try:
            manifest_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {manifest_path} is not valid JSON.")

    assert isinstance(manifest_data, list), "Manifest must be a JSON array."

    expected_paths = {
        '/home/user/app_data/new_data.csv',
        '/home/user/app_data/nested/new_config.xml',
        '/home/user/app_data/new_settings.json'
    }

    actual_paths = set(manifest_data)
    assert actual_paths == expected_paths, f"Manifest contents do not match. Expected {expected_paths}, got {actual_paths}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
