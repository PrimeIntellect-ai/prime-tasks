#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_organizer.py
import os
import secrets
import shutil
import stat
import subprocess
import zipfile

SOURCE = '/home/user/organizer.cpp'
EXECUTABLE = '/home/user/organizer'
LOG = '/home/user/backup_history.log'
VALID_DIR = '/home/user/valid_backups'


def test_00_required_artifacts_exist_and_are_valid():
    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), \
        f'Expected {SOURCE} to be a regular C++ source file.'
    assert os.path.isfile(EXECUTABLE) and not os.path.islink(EXECUTABLE), \
        f'Expected {EXECUTABLE} to be a regular executable file.'
    assert os.access(EXECUTABLE, os.X_OK), f'{EXECUTABLE} is not executable.'
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{EXECUTABLE} is not a compiled ELF executable.'


def test_01_v1_link_exists_and_correct():
    link_path = '/home/user/valid_backups/v1.0_link.zip'
    target_path = '/home/user/archives/backup1.zip'

    assert os.path.exists(link_path), f'Expected link {link_path} does not exist.'
    assert os.path.islink(link_path), f'{link_path} exists but is not a symbolic link.'

    actual_target = os.readlink(link_path)
    assert actual_target == target_path, f'Link {link_path} points to {actual_target}, expected {target_path}.'


def test_02_v2_link_exists_and_correct():
    link_path = '/home/user/valid_backups/v2.0_link.zip'
    target_path = '/home/user/archives/backup2.zip'

    assert os.path.exists(link_path), f'Expected link {link_path} does not exist.'
    assert os.path.islink(link_path), f'{link_path} exists but is not a symbolic link.'

    actual_target = os.readlink(link_path)
    assert actual_target == target_path, f'Link {link_path} points to {actual_target}, expected {target_path}.'


def test_03_v3_link_does_not_exist():
    link_path = '/home/user/valid_backups/v3.0_link.zip'
    assert not os.path.exists(link_path) and not os.path.islink(link_path), \
        f'Link {link_path} should not exist because the archive is corrupted.'


def test_04_no_unexpected_links():
    if os.path.isdir(VALID_DIR):
        expected_files = {'v1.0_link.zip', 'v2.0_link.zip'}
        actual_files = set(os.listdir(VALID_DIR))
        unexpected = actual_files - expected_files
        assert not unexpected, f'Found unexpected files in {VALID_DIR}: {unexpected}'


def run_dynamic_scenario(program, scenario_dir, version_good, version_bad):
    shutil.rmtree(scenario_dir, ignore_errors=True)
    os.makedirs(scenario_dir)
    good_zip = os.path.join(scenario_dir, 'intact.zip')
    bad_zip = os.path.join(scenario_dir, 'damaged.zip')

    with zipfile.ZipFile(good_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('payload.txt', secrets.token_bytes(128))
    with zipfile.ZipFile(bad_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('payload.txt', secrets.token_bytes(128))
    with open(bad_zip, 'r+b') as f:
        f.truncate(max(1, os.path.getsize(bad_zip) // 3))

    with open(LOG, 'w') as f:
        f.write(
            f'Record Start\nVersion: {version_good}\nArchive: {good_zip}\nStatus: complete\n\n'
            f'Record Start\nVersion: {version_bad}\nArchive: {bad_zip}\nStatus: complete\n'
        )

    shutil.rmtree(VALID_DIR, ignore_errors=True)
    os.makedirs(VALID_DIR)
    subprocess.run([program], check=True, timeout=20)

    good_link = os.path.join(VALID_DIR, f'{version_good}_link.zip')
    bad_link = os.path.join(VALID_DIR, f'{version_bad}_link.zip')
    assert os.path.islink(good_link), f'{program} did not create the link for an intact archive.'
    assert os.readlink(good_link) == good_zip, f'{program} created a link with the wrong target.'
    assert not os.path.exists(bad_link) and not os.path.islink(bad_link), \
        f'{program} created a link for a corrupted archive.'
    assert set(os.listdir(VALID_DIR)) == {f'{version_good}_link.zip'}, \
        f'{program} produced unexpected output files.'


def test_10_execute_artifact_and_source_on_derived_inputs():
    token = secrets.randbelow(800000) + 100000
    run_dynamic_scenario(EXECUTABLE, f'/tmp/organizer_case_{token}_installed',
                         f'v{token}.1', f'v{token}.2')

    rebuilt = f'/tmp/organizer_rebuilt_{token}'
    result = subprocess.run(
        ['g++', '-std=c++17', SOURCE, '-o', rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f'organizer.cpp failed to compile:\n{result.stderr}'
    mode = os.stat(rebuilt).st_mode
    assert stat.S_ISREG(mode) and os.access(rebuilt, os.X_OK)
    run_dynamic_scenario(rebuilt, f'/tmp/organizer_case_{token}_rebuilt',
                         f'v{token}.3', f'v{token}.4')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_organizer.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
