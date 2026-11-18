#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import secrets
import shutil
import subprocess
import sys
import tarfile
import zipfile

import pytest


def test_process_script_exists():
    script_path = '/home/user/process_backups.py'
    assert os.path.isfile(script_path), f"File {script_path} does not exist or is not a regular file."


def test_security_report_json():
    """Test that the security_report.json file exists and contains the correct malicious paths."""
    report_path = '/home/user/security_report.json'
    assert os.path.isfile(report_path), f"File {report_path} does not exist."

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    expected_data = {
        "user_profiles.zip": ["../../../home/user/.bashrc"],
        "core_sys.zip": ["/etc/shadow"]
    }

    assert report_data == expected_data, f"Contents of {report_path} do not match the expected security report."


def test_extracted_files_exist():
    """Test that the safe files were extracted and CSV was converted."""
    extracted_dir = '/home/user/extracted'

    assert os.path.isfile(os.path.join(extracted_dir, 'users.json')), "users.json was not found in the extracted directory."
    assert os.path.isfile(os.path.join(extracted_dir, 'readme.txt')), "readme.txt was not found in the extracted directory."
    assert os.path.isfile(os.path.join(extracted_dir, 'config.bin')), "config.bin was not found in the extracted directory."


def test_extracted_users_json_content():
    """Test that users.json contains the correct parsed CSV data."""
    users_json_path = '/home/user/extracted/users.json'

    with open(users_json_path, 'r') as f:
        try:
            users_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {users_json_path} is not valid JSON.")

    expected_users = [
        {"id": "1", "username": "admin", "role": "superuser"},
        {"id": "2", "username": "bob", "role": "editor"}
    ]

    assert users_data == expected_users, f"Contents of {users_json_path} do not match expected parsed CSV data."


def test_extracted_readme_txt_content():
    """Test that readme.txt contains the correct text."""
    readme_path = '/home/user/extracted/readme.txt'
    with open(readme_path, 'r') as f:
        content = f.read()
    assert content == 'Backup instructions.', "Contents of readme.txt are incorrect."


def test_extracted_config_bin_content():
    """Test that config.bin contains the correct binary data."""
    config_path = '/home/user/extracted/config.bin'
    with open(config_path, 'rb') as f:
        content = f.read()
    assert content == b'\x00\x01\x02\x03\x04', "Contents of config.bin are incorrect."


def test_users_csv_removed():
    """Test that the original users.csv file was deleted after conversion."""
    csv_path = '/home/user/extracted/users.csv'
    assert not os.path.exists(csv_path), "The original users.csv file was not deleted."


def test_malicious_files_not_extracted():
    """Test that files from malicious zips were not extracted."""
    extracted_dir = '/home/user/extracted'
    malicious_files = [
        'safe_file.txt',
        'normal_dir/path.txt',
        'normal_dir',
        '.bashrc',
        'shadow'
    ]

    for m_file in malicious_files:
        path = os.path.join(extracted_dir, m_file)
        assert not os.path.exists(path), f"Malicious or associated file {m_file} was incorrectly extracted."


def test_script_processes_runtime_generated_backup():
    """Execute the submitted script against a fresh, unpredictable backup fixture."""
    token = secrets.token_hex(12)
    incoming_dir = '/home/user/incoming'
    backup_path = os.path.join(incoming_dir, 'backup.tar')
    extracted_dir = '/home/user/extracted'
    report_path = '/home/user/security_report.json'
    script_path = '/home/user/process_backups.py'

    safe_archive_1 = f'safe_data_{token}.zip'
    safe_archive_2 = f'safe_binary_{token}.zip'
    malicious_archive_1 = f'traversal_{token}.zip'
    malicious_archive_2 = f'absolute_{token}.zip'
    csv_name = f'records_{token}.csv'
    json_name = f'records_{token}.json'
    text_name = f'note_{token}.txt'
    binary_name = f'blob_{token}.bin'
    malicious_decoy_1 = f'decoy_one_{token}.txt'
    malicious_decoy_2 = f'decoy_two_{token}.txt'
    traversal_target = f'/tmp/traversal_target_{token}'
    absolute_target = f'/tmp/absolute_target_{token}'
    traversal_path = f'../../../tmp/traversal_target_{token}'
    absolute_path = absolute_target

    rows = [
        {'key': token[:8], 'value': f'alpha-{token}'},
        {'key': token[8:16], 'value': f'beta-{token}'},
    ]
    csv_buffer = io.StringIO(newline='')
    writer = csv.DictWriter(csv_buffer, fieldnames=['key', 'value'], lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
    text_content = f'Runtime backup content: {token}'
    binary_content = secrets.token_bytes(37)

    temporary_zips = []
    try:
        for path in (traversal_target, absolute_target):
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.remove(path)

        zip_specs = [
            (safe_archive_1, [(csv_name, csv_buffer.getvalue()), (text_name, text_content)]),
            (safe_archive_2, [(binary_name, binary_content)]),
            (malicious_archive_1, [(malicious_decoy_1, 'must not be extracted'), (traversal_path, 'escaped')]),
            (malicious_archive_2, [(absolute_path, 'escaped'), (malicious_decoy_2, 'must not be extracted')]),
        ]

        for archive_name, members in zip_specs:
            zip_path = os.path.join('/tmp', f'{token}_{archive_name}')
            temporary_zips.append(zip_path)
            with zipfile.ZipFile(zip_path, 'w') as archive:
                for member_name, content in members:
                    archive.writestr(member_name, content)

        os.makedirs(incoming_dir, exist_ok=True)
        with tarfile.open(backup_path, 'w') as backup:
            for (archive_name, _), zip_path in zip(zip_specs, temporary_zips):
                backup.add(zip_path, arcname=archive_name)

        if os.path.exists(extracted_dir):
            shutil.rmtree(extracted_dir)
        os.makedirs(extracted_dir)
        if os.path.lexists(report_path):
            os.remove(report_path)

        result = subprocess.run(
            [sys.executable, script_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"process_backups.py exited with {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert os.path.isfile(report_path), 'The executed script did not create security_report.json.'
        with open(report_path, 'r') as report_file:
            report = json.load(report_file)
        assert report == {
            malicious_archive_1: [traversal_path],
            malicious_archive_2: [absolute_path],
        }

        converted_path = os.path.join(extracted_dir, json_name)
        assert os.path.isfile(converted_path), 'The runtime CSV was not converted to JSON.'
        with open(converted_path, 'r') as converted_file:
            assert json.load(converted_file) == rows
        assert not os.path.exists(os.path.join(extracted_dir, csv_name)), 'The runtime CSV was not deleted.'

        with open(os.path.join(extracted_dir, text_name), 'r') as text_file:
            assert text_file.read() == text_content
        with open(os.path.join(extracted_dir, binary_name), 'rb') as binary_file:
            assert binary_file.read() == binary_content

        actual_files = set()
        for root, _, files in os.walk(extracted_dir):
            for filename in files:
                actual_files.add(os.path.relpath(os.path.join(root, filename), extracted_dir))
        assert actual_files == {json_name, text_name, binary_name}, (
            f'Malicious or unexpected archive members were extracted: {actual_files}'
        )

        assert not os.path.exists(traversal_target), 'A parent-traversal member escaped the extraction directory.'
        assert not os.path.exists(absolute_target), 'An absolute-path member escaped the extraction directory.'
        assert not os.path.exists(os.path.join(extracted_dir, malicious_decoy_1))
        assert not os.path.exists(os.path.join(extracted_dir, malicious_decoy_2))
    finally:
        for zip_path in temporary_zips:
            if os.path.exists(zip_path):
                os.remove(zip_path)
        for path in (traversal_target, absolute_target):
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
