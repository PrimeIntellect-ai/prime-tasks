#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import py_compile
import shutil
import stat
import subprocess
import uuid
import zipfile
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/config_manager.py')
LEDGER = Path('/home/user/config_ledger.txt')
REJECTED = Path('/home/user/rejected_updates.log')


def test_00_script_exists_and_processes_supplied_archive():
    assert SCRIPT.is_file(), f"Required script {SCRIPT} does not exist."
    assert stat.S_ISREG(SCRIPT.stat().st_mode), f"{SCRIPT} is not a regular file."
    py_compile.compile(str(SCRIPT), doraise=True)

    LEDGER.unlink(missing_ok=True)
    REJECTED.unlink(missing_ok=True)
    shutil.rmtree('/home/user/app_configs', ignore_errors=True)
    os.makedirs('/home/user/app_configs', exist_ok=True)

    result = subprocess.run(
        ['python3', str(SCRIPT), '/home/user/incoming/updates.zip', '/home/user/app_configs'],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"config_manager.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_rejected_updates_log():
    log_path = "/home/user/rejected_updates.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = set(line.strip() for line in f if line.strip())

    expected_lines = {
        "../../../home/user/.bash_profile",
        "plugins/../../shadow_backup.conf"
    }

    assert lines == expected_lines, f"Expected {expected_lines} in rejected_updates.log, but got {lines}."


def test_config_ledger():
    ledger_path = "/home/user/config_ledger.txt"
    assert os.path.isfile(ledger_path), f"File {ledger_path} does not exist."

    with open(ledger_path, 'r') as f:
        lines = set(line.strip() for line in f if line.strip())

    expected_lines = {
        "[UPDATE] network.conf | port=8080",
        "[UPDATE] network.conf | host=0.0.0.0",
        "[UPDATE] plugins/db.conf | engine=sqlite",
        "[UPDATE] plugins/db.conf | workers=4"
    }

    assert lines == expected_lines, f"Expected {expected_lines} in config_ledger.txt, but got {lines}."


def test_extracted_files_exist():
    file1 = "/home/user/app_configs/network.conf"
    file2 = "/home/user/app_configs/plugins/db.conf"

    assert os.path.isfile(file1), f"Valid extracted file {file1} is missing."
    assert os.path.isfile(file2), f"Valid extracted file {file2} is missing."


def test_extracted_file_contents():
    assert Path('/home/user/app_configs/network.conf').read_text() == 'port=8080\nhost=0.0.0.0\n'
    assert Path('/home/user/app_configs/plugins/db.conf').read_text() == 'engine=sqlite\nworkers=4\n'


def test_malicious_files_not_extracted():
    # Check that the malicious files were not extracted
    file1 = "/home/user/.bash_profile"
    file2 = "/home/user/shadow_backup.conf"

    if os.path.exists(file1):
        with open(file1, 'r') as f:
            content = f.read()
            assert 'echo "hacked"' not in content, f"Malicious content found in {file1}."

    assert not os.path.exists(file2), f"Malicious file {file2} was extracted!"


def test_z_randomized_archive_behavior():
    token = uuid.uuid4().hex
    root = Path('/tmp') / f'cfg_verify_{token}'
    target = root / 'app_configs'
    archive = root / f'updates_{token}.zip'
    target.mkdir(parents=True)

    safe_files = {
        f'service_{token}.conf': f'port_{token}=91\nhost_{token}=localhost\n',
        f'plugins_{token}/db_{token}.conf': f'engine_{token}=sqlite\nworkers_{token}=7\n',
    }
    unsafe_files = {
        f'../escaped_{token}.conf': f'outside_{token}=bad\n',
        f'nested/../../escaped2_{token}.conf': f'outside2_{token}=bad\n',
    }

    with zipfile.ZipFile(archive, 'w') as zf:
        for name, content in safe_files.items():
            zf.writestr(name, content)
        for name, content in unsafe_files.items():
            zf.writestr(name, content)

    LEDGER.unlink(missing_ok=True)
    REJECTED.unlink(missing_ok=True)

    result = subprocess.run(
        ['python3', str(SCRIPT), str(archive), str(target)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"config_manager.py failed on a generated archive.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    for relative_name, expected_content in safe_files.items():
        extracted = target / relative_name
        assert extracted.is_file(), f"Safe archive member {relative_name} was not extracted."
        assert extracted.read_text() == expected_content

    expected_extracted = {str((target / name).resolve()) for name in safe_files}
    actual_extracted = {str(path.resolve()) for path in target.rglob('*') if path.is_file()}
    assert actual_extracted == expected_extracted, (
        f"Unexpected extracted files: {actual_extracted - expected_extracted}"
    )

    for member_name in unsafe_files:
        resolved_destination = (target / member_name).resolve()
        assert not resolved_destination.exists(), f"Unsafe member escaped to {resolved_destination}."
        assert not (target / Path(member_name).name).exists(), (
            f"Unsafe member {member_name} was sanitized and extracted instead of rejected."
        )

    assert REJECTED.is_file(), 'Randomized run did not create rejected_updates.log.'
    rejected_lines = {line.strip() for line in REJECTED.read_text().splitlines() if line.strip()}
    assert rejected_lines == set(unsafe_files), (
        f"Expected rejected members {set(unsafe_files)}, got {rejected_lines}."
    )

    expected_ledger = set()
    for relative_name, content in safe_files.items():
        for property_line in content.splitlines():
            if property_line:
                expected_ledger.add(f'[UPDATE] {relative_name} | {property_line}')

    assert LEDGER.is_file(), 'Randomized run did not create config_ledger.txt.'
    ledger_lines = {line.strip() for line in LEDGER.read_text().splitlines() if line.strip()}
    assert ledger_lines == expected_ledger, (
        f"Expected ledger entries {expected_ledger}, got {ledger_lines}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
