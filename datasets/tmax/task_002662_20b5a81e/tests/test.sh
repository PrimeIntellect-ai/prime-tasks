#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import stat
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import zipfile
import pytest


def test_config_diff_csv():
    csv_path = "/home/user/config_diff.csv"
    assert os.path.exists(csv_path), f"The file {csv_path} does not exist."
    assert os.path.isfile(csv_path), f"The path {csv_path} is not a file."

    expected_rows = [
        ["Key", "V1_Value", "V3_Value"],
        ["app_name", "myapp", "myapp_v2"],
        ["db_host", "localhost", "db.prod"],
        ["debug", "False", "True"],
        ["port", "8080", "8081"]
    ]

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert actual_rows == expected_rows, f"The contents of {csv_path} do not match the expected diff. Found: {actual_rows}"


def test_skipped_files_log():
    log_path = "/home/user/skipped_files.log"
    assert os.path.exists(log_path), f"The file {log_path} does not exist."
    assert os.path.isfile(log_path), f"The path {log_path} is not a file."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_paths = [
        "../escaped_system_config.json",
        "v2/../../etc/passwd_fake"
    ]

    for path in expected_paths:
        assert path in lines, f"The malicious path '{path}' was not found in {log_path}."


def test_no_zip_slip_files():
    # Check that the malicious files were not extracted outside the target directory
    escaped_file_1 = "/home/user/escaped_system_config.json"
    escaped_file_2 = "/home/user/etc/passwd_fake"
    escaped_file_3 = "/home/user/extracted_configs/../escaped_system_config.json"
    escaped_file_4 = "/home/user/extracted_configs/v2/../../etc/passwd_fake"

    # Normalize paths to check actual locations
    check_paths = [
        os.path.normpath(escaped_file_1),
        os.path.normpath(escaped_file_2),
        os.path.normpath(escaped_file_3),
        os.path.normpath(escaped_file_4)
    ]

    for path in check_paths:
        assert not os.path.exists(path), f"Security failure: Malicious file was extracted to {path}!"


def test_extracted_configs():
    v1_config = "/home/user/extracted_configs/v1/config.json"
    v3_config = "/home/user/extracted_configs/v3/config.json"

    assert os.path.exists(v1_config), f"The file {v1_config} was not extracted."
    assert os.path.isfile(v1_config), f"The path {v1_config} is not a file."

    assert os.path.exists(v3_config), f"The file {v3_config} was not extracted."
    assert os.path.isfile(v3_config), f"The path {v3_config} is not a file."


def test_safe_extract_script_on_fresh_archive():
    script = "/home/user/safe_extract.py"
    assert os.path.exists(script), f"The required script {script} does not exist."
    assert stat.S_ISREG(os.lstat(script).st_mode), f"The path {script} is not a regular file."
    assert os.path.getsize(script) > 0, f"The script {script} is empty."

    token = uuid.uuid4().hex
    safe_member = f"probe_{token}/payload.txt"
    safe_content = f"safe payload {token}"
    malicious_members = [
        f"../escaped_{token}.json",
        f"v2/../../etc/passwd_{token}",
        f"/tmp/absolute_{token}.txt",
    ]
    outside_paths = [
        f"/home/user/escaped_{token}.json",
        f"/home/user/etc/passwd_{token}",
        f"/tmp/absolute_{token}.txt",
    ]

    for path in outside_paths:
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)

    # Replace both the tarball and any already-unpacked ZIPs with a fresh,
    # unpredictable test case so a hard-coded log or fabricated output cannot pass.
    for root, dirs, files in os.walk('/home/user'):
        for name in files:
            if name.lower().endswith('.zip'):
                os.remove(os.path.join(root, name))

    with tempfile.TemporaryDirectory() as td:
        part1 = os.path.join(td, 'part1.zip')
        part2 = os.path.join(td, 'part2.zip')
        part3 = os.path.join(td, 'part3.zip')

        with zipfile.ZipFile(part1, 'w') as z:
            z.writestr(safe_member, safe_content)
            z.writestr('v1/config.json', json.dumps({'value': f'v1-{token}'}))
        with zipfile.ZipFile(part2, 'w') as z:
            for member in malicious_members:
                z.writestr(member, f'malicious {token}')
        with zipfile.ZipFile(part3, 'w') as z:
            z.writestr('v3/config.json', json.dumps({'value': f'v3-{token}'}))

        archive = '/home/user/config_backup.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            tar.add(part1, arcname='part1.zip')
            tar.add(part2, arcname='part2.zip')
            tar.add(part3, arcname='part3.zip')

        # Also provide the unpacked ZIPs because the instruction permits extracting
        # the tarball as a separate step before running safe_extract.py.
        for source in (part1, part2, part3):
            shutil.copy2(source, os.path.join('/home/user', os.path.basename(source)))

    extracted = '/home/user/extracted_configs'
    shutil.rmtree(extracted, ignore_errors=True)
    os.makedirs(extracted, mode=0o777)
    os.chmod(extracted, 0o777)
    log_path = '/home/user/skipped_files.log'
    if os.path.lexists(log_path):
        os.remove(log_path)

    result = subprocess.run(
        ['/usr/sbin/runuser', '-u', 'user', '--', 'python3', script],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{script} failed when executed on a fresh archive. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    safe_path = os.path.join(extracted, safe_member)
    assert os.path.isfile(safe_path), f"The safe member {safe_member} was not extracted."
    with open(safe_path, 'r') as f:
        assert f.read() == safe_content, "The safely extracted probe file had incorrect contents."

    assert os.path.isfile(log_path), f"The script did not create {log_path}."
    with open(log_path, 'r') as f:
        logged = [line.strip() for line in f if line.strip()]
    for member in malicious_members:
        assert member in logged, f"The fresh malicious path {member!r} was not logged."

    for path in outside_paths:
        assert not os.path.lexists(path), f"Security failure: malicious member escaped to {path}."

    for root, dirs, files in os.walk(extracted):
        for name in dirs + files:
            assert token not in name or os.path.join(root, name) == safe_path, (
                f"A malicious probe member was created inside the extraction tree: {os.path.join(root, name)}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
