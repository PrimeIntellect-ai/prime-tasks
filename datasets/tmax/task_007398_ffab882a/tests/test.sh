#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import uuid
import zipfile


def test_script_exists_and_is_regular_file():
    script_path = '/home/user/safe_deploy.py'
    assert os.path.exists(script_path), f"Expected script {script_path} does not exist."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"Expected {script_path} to be a regular file."


def test_safe_extraction_valid_files():
    valid_file_path = '/home/user/project_data/valid_file.txt'
    deep_file_path = '/home/user/project_data/nested/deep_file.txt'

    assert os.path.isfile(valid_file_path), f"Expected file {valid_file_path} does not exist."
    with open(valid_file_path, 'r') as f:
        assert f.read() == 'This is a valid file.', f"Content of {valid_file_path} is incorrect."

    assert os.path.isfile(deep_file_path), f"Expected file {deep_file_path} does not exist."
    with open(deep_file_path, 'r') as f:
        assert f.read() == 'This is a deep file.', f"Content of {deep_file_path} is incorrect."


def test_safe_extraction_zip_slip_protection():
    escaped_file_path = '/home/user/escaped_file.txt'
    sneaky_file_path = '/home/user/sneaky.txt'

    assert not os.path.exists(escaped_file_path), f"Zip Slip vulnerability detected: {escaped_file_path} was extracted."
    assert not os.path.exists(sneaky_file_path), f"Zip Slip vulnerability detected: {sneaky_file_path} was extracted."


def test_symlink_creation():
    symlink_path = '/home/user/latest.txt'
    target_path = '/home/user/project_data/valid_file.txt'

    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symbolic link."
    assert os.readlink(symlink_path) == target_path, f"Symlink {symlink_path} does not point to {target_path}."


def test_hard_link_backup():
    orig_valid = '/home/user/project_data/valid_file.txt'
    backup_valid = '/home/user/new_backup/valid_file.txt'

    orig_deep = '/home/user/project_data/nested/deep_file.txt'
    backup_deep = '/home/user/new_backup/nested/deep_file.txt'

    assert os.path.isfile(backup_valid), f"Backup file {backup_valid} does not exist."
    stat_orig = os.stat(orig_valid)
    stat_backup = os.stat(backup_valid)
    assert stat_orig.st_ino == stat_backup.st_ino, f"{backup_valid} is not a hard link to {orig_valid}."

    assert os.path.isfile(backup_deep), f"Backup file {backup_deep} does not exist."
    stat_orig_deep = os.stat(orig_deep)
    stat_backup_deep = os.stat(backup_deep)
    assert stat_orig_deep.st_ino == stat_backup_deep.st_ino, f"{backup_deep} is not a hard link to {orig_deep}."


def _remove(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def test_script_executes_and_handles_unseen_archive_entries_safely():
    token = uuid.uuid4().hex
    archive = '/home/user/incoming.zip'
    destination = '/home/user/project_data'
    backup = '/home/user/new_backup'
    symlink = '/home/user/latest.txt'

    nested_name = f'nested/generated_{token}.txt'
    escape_name = f'../escape_{token}.txt'
    sneaky_name = f'nested/../../../sneaky_{token}.txt'
    valid_content = f'valid-{token}'
    nested_content = f'nested-{token}'

    outside_targets = [
        os.path.abspath(os.path.join(destination, escape_name)),
        os.path.abspath(os.path.join(destination, sneaky_name)),
    ]

    _remove(destination)
    _remove(backup)
    _remove(symlink)
    for path in outside_targets:
        _remove(path)

    with zipfile.ZipFile(archive, 'w') as zf:
        zf.writestr('valid_file.txt', valid_content)
        zf.writestr(nested_name, nested_content)
        zf.writestr(escape_name, f'escape-{token}')
        zf.writestr(sneaky_name, f'sneaky-{token}')

    result = subprocess.run(
        ['python3', '/home/user/safe_deploy.py'],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"safe_deploy.py failed when executed. stdout={result.stdout!r} stderr={result.stderr!r}"
    )

    valid_path = os.path.join(destination, 'valid_file.txt')
    nested_path = os.path.join(destination, nested_name)
    assert os.path.isfile(valid_path), f"Expected dynamically supplied file {valid_path} does not exist."
    assert os.path.isfile(nested_path), f"Expected dynamically supplied file {nested_path} does not exist."
    with open(valid_path, 'r') as f:
        assert f.read() == valid_content
    with open(nested_path, 'r') as f:
        assert f.read() == nested_content

    for path in outside_targets:
        assert not os.path.lexists(path), f"Zip Slip vulnerability detected: {path} was created."

    malicious_basenames = {os.path.basename(escape_name), os.path.basename(sneaky_name)}
    for root in (destination, backup):
        for current, dirs, files in os.walk(root):
            assert malicious_basenames.isdisjoint(files), (
                f"A traversal entry was extracted instead of being skipped under {current}."
            )

    assert os.path.islink(symlink), f"Expected {symlink} to be a symbolic link."
    assert os.readlink(symlink) == valid_path, f"Symlink {symlink} does not point to {valid_path}."

    for relative_path in ('valid_file.txt', nested_name):
        original = os.path.join(destination, relative_path)
        copied = os.path.join(backup, relative_path)
        assert os.path.isfile(copied), f"Backup file {copied} does not exist."
        original_stat = os.stat(original)
        copied_stat = os.stat(copied)
        assert (original_stat.st_dev, original_stat.st_ino) == (copied_stat.st_dev, copied_stat.st_ino), (
            f"{copied} is not a hard link to {original}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
