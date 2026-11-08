#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import subprocess
import tarfile

import pytest

BACKUP_V1_PATH = '/home/user/backup_v1.tar.gz'
BACKUP_V2_PATH = '/home/user/backup_v2.tar.gz'
PROJECT_DIR = '/home/user/project'
SCRIPT_PATH = '/home/user/make_backup.py'


def read_regular_members(path):
    result = {}
    with tarfile.open(path, 'r:gz') as tar:
        for member in tar.getmembers():
            if member.isfile():
                extracted = tar.extractfile(member)
                assert extracted is not None
                result[member.name] = extracted.read()
    return result


def prepare_and_run_submission():
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} not found or is not a regular file'
    assert not os.path.islink(SCRIPT_PATH), f'{SCRIPT_PATH} must be a real Python script, not a symlink'
    with open(SCRIPT_PATH, 'rb') as script_file:
        source = script_file.read()
    compile(source, SCRIPT_PATH, 'exec')

    # Add opaque comparison probes. One is identical to its archived version,
    # one is modified, and one is new. Their random names and contents force
    # the submitted script to compare the project against backup_v1.
    names = [f'probe_{secrets.token_hex(10)}.bin' for _ in range(3)]
    unchanged_name, changed_name, new_name = names
    unchanged_data = os.urandom(137)
    changed_old_data = os.urandom(149)
    changed_new_data = os.urandom(151)
    new_data = os.urandom(163)

    with open(os.path.join(PROJECT_DIR, unchanged_name), 'wb') as f:
        f.write(unchanged_data)
    with open(os.path.join(PROJECT_DIR, changed_name), 'wb') as f:
        f.write(changed_new_data)
    with open(os.path.join(PROJECT_DIR, new_name), 'wb') as f:
        f.write(new_data)

    replacement = BACKUP_V1_PATH + '.verifier_tmp'
    with tarfile.open(BACKUP_V1_PATH, 'r:gz') as source_tar, tarfile.open(replacement, 'w:gz') as dest_tar:
        for member in source_tar.getmembers():
            if member.isfile():
                extracted = source_tar.extractfile(member)
                assert extracted is not None
                dest_tar.addfile(member, io.BytesIO(extracted.read()))
            else:
                dest_tar.addfile(member)
        for name, data in ((unchanged_name, unchanged_data), (changed_name, changed_old_data)):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            dest_tar.addfile(info, io.BytesIO(data))
    os.replace(replacement, BACKUP_V1_PATH)

    if os.path.lexists(BACKUP_V2_PATH):
        os.remove(BACKUP_V2_PATH)

    completed = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'{SCRIPT_PATH} failed with exit code {completed.returncode}\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} must still exist after execution'
    return unchanged_name, changed_name, new_name


UNCHANGED_PROBE, CHANGED_PROBE, NEW_PROBE = prepare_and_run_submission()


def expected_differential():
    archived = read_regular_members(BACKUP_V1_PATH)
    expected = {}

    for entry in os.scandir(PROJECT_DIR):
        if not entry.is_file(follow_symlinks=False):
            continue
        with open(entry.path, 'rb') as f:
            current = f.read()

        if entry.name == 'app.log':
            assert 'app.log' in archived, 'backup_v1 is missing app.log'
            old = archived['app.log']
            assert current.startswith(old), 'current app.log is not an append-only extension of archived app.log'
            suffix = current[len(old):]
            if suffix:
                expected['app_diff.log'] = suffix
        elif entry.name not in archived or current != archived[entry.name]:
            expected[entry.name] = current

    return expected


def test_backup_v2_exists():
    assert os.path.exists(BACKUP_V2_PATH), f'{BACKUP_V2_PATH} not found'
    assert os.path.isfile(BACKUP_V2_PATH), f'{BACKUP_V2_PATH} is not a regular file'


def test_backup_v2_contents_are_exact():
    expected = expected_differential()
    with tarfile.open(BACKUP_V2_PATH, 'r:gz') as tar:
        members = tar.getmembers()
        names = [member.name for member in members]

        # Preserve the original required and excluded member assertions.
        assert 'app_diff.log' in names, 'app_diff.log not found in the archive'
        assert 'data.bin' in names, 'data.bin not found in the archive'
        assert 'static.bin' not in names, 'static.bin should not be in the archive (it is unchanged)'
        assert 'app.log' not in names, 'app.log should not be in the archive (should be app_diff.log)'

        # Require exactly the derived differential: no extras, duplicates,
        # directories, links, or other non-file archive entries.
        assert len(names) == len(set(names)), 'archive contains duplicate member names'
        assert set(names) == set(expected), f'archive members mismatch: expected {sorted(expected)}, got {sorted(names)}'
        assert all(member.isfile() for member in members), 'all differential archive members must be regular files'

        for name, expected_data in expected.items():
            extracted = tar.extractfile(name)
            assert extracted is not None
            assert extracted.read() == expected_data, f'{name} content does not match the derived differential'

        # Probe-specific comparison assertions.
        assert UNCHANGED_PROBE not in names, 'a file identical to backup_v1 was incorrectly included'
        assert CHANGED_PROBE in names, 'a modified file was not included'
        assert NEW_PROBE in names, 'a new file was not included'


def test_app_diff_log_content():
    with tarfile.open(BACKUP_V2_PATH, 'r:gz') as tar:
        assert 'app_diff.log' in tar.getnames(), 'app_diff.log not found in the archive'
        extracted = tar.extractfile('app_diff.log')
        assert extracted is not None
        content = extracted.read().decode('utf-8').strip()
        expected = '2023-10-01 10:15:00 ERROR Out of memory\n2023-10-01 10:20:00 INFO Restarting'
        assert content == expected, f'app_diff.log content mismatch. Expected:\n{expected}\nGot:\n{content}'


def test_data_bin_content():
    with tarfile.open(BACKUP_V2_PATH, 'r:gz') as tar:
        assert 'data.bin' in tar.getnames(), 'data.bin not found in the archive'
        extracted = tar.extractfile('data.bin')
        assert extracted is not None
        archived_data = extracted.read()

    curr_data_path = os.path.join(PROJECT_DIR, 'data.bin')
    assert os.path.exists(curr_data_path), f'{curr_data_path} is missing from the filesystem'
    with open(curr_data_path, 'rb') as curr_data:
        expected_data = curr_data.read()
    assert archived_data == expected_data, 'data.bin in the archive does not match the current project data.bin'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
