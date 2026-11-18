#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import pytest


def test_symlink_exists_and_correct():
    symlink_path = '/home/user/latest_archive'
    assert os.path.islink(symlink_path), f"Symlink {symlink_path} does not exist or is not a symlink."

    target = os.readlink(symlink_path)
    expected_targets = ['/home/user/logs/archive.tar.gz', 'logs/archive.tar.gz']
    assert target in expected_targets, f"Symlink points to {target}, expected one of {expected_targets}."


def test_archive_size():
    archive_path = '/home/user/logs/archive.tar.gz'
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."

    size = os.path.getsize(archive_path)
    threshold = 180
    assert size <= threshold, f"Archive size is {size} bytes, which exceeds the threshold of {threshold} bytes. Did you use maximum compression?"


def test_archive_contents():
    archive_path = '/home/user/logs/archive.tar.gz'
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."

    expected_files = ['sanitized_service1.log', 'sanitized_service2.log', 'sanitized_service3.log']

    with tarfile.open(archive_path, 'r:gz') as tar:
        # Get basenames of files in the archive
        archive_members = [os.path.basename(m.name) for m in tar.getmembers() if m.isfile()]

        for expected in expected_files:
            assert expected in archive_members, f"Expected file {expected} not found in the archive."

        # Check contents
        for member in tar.getmembers():
            if not member.isfile() or not member.name.endswith('.log'):
                continue

            f = tar.extractfile(member)
            content = f.read().decode('utf-8')

            assert "SECRET_KEY" not in content, f"Found unreplaced 'SECRET_KEY' in {member.name} inside the archive."
            assert "REDACTED_KEY" in content, f"Expected 'REDACTED_KEY' not found in {member.name} inside the archive."


def test_archived_logs_preserve_transformed_original_contents():
    archive_path = '/home/user/logs/archive.tar.gz'
    target = 'SECRET_KEY'
    replacement = 'REDACTED_KEY'
    prefix = 'sanitized_'
    original_logs = {
        'service1.log': (
            'INFO: Starting up\n'
            'DEBUG: Found SECRET_KEY in env\n'
            'ERROR: SECRET_KEY is invalid\n'
        ),
        'service2.log': (
            'INFO: Processing jobs\n'
            'WARN: Retrying connection using SECRET_KEY...\n'
        ),
        'service3.log': (
            'SECRET_KEY\n'
            'Nothing to see here.\n'
        ),
    }
    expected_contents = {
        prefix + name: content.replace(target, replacement).encode('utf-8')
        for name, content in original_logs.items()
    }

    with tarfile.open(archive_path, 'r:gz') as tar:
        regular_members = [member for member in tar.getmembers() if member.isfile()]
        for expected_name, expected_content in expected_contents.items():
            matches = [
                member for member in regular_members
                if os.path.basename(member.name) == expected_name
            ]
            assert len(matches) == 1, (
                f"Expected exactly one regular file named {expected_name}, found {len(matches)}."
            )
            archived_content = tar.extractfile(matches[0]).read()
            assert archived_content == expected_content, (
                f"{expected_name} does not exactly preserve the original log content "
                f"with all {target!r} occurrences replaced by {replacement!r}."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
