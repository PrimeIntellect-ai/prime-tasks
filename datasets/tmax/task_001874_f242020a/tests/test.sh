#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import gzip
import bz2
import tarfile
import pytest

def get_config():
    config_path = "/home/user/backup_config.json"
    assert os.path.exists(config_path), f"Config file missing at {config_path}"
    with open(config_path, 'r') as f:
        return json.load(f)

def get_expected_entries():
    config = get_config()
    target_magic_str = config.get("target_magic", "")
    # Convert escaped string like "PG_WAL\\x00\\x01" to actual bytes
    target_magic = target_magic_str.encode('utf-8').decode('unicode_escape').encode('latin-1')

    expected_entries = []
    backup_dir = "/home/user/wal_backups"

    for root, _, files in os.walk(backup_dir):
        for f in files:
            path = os.path.join(root, f)
            try:
                if f.endswith('.gz'):
                    with gzip.open(path, 'rb') as gz:
                        header = gz.read(8)
                elif f.endswith('.bz2'):
                    with bz2.open(path, 'rb') as bz:
                        header = bz.read(8)
                else:
                    with open(path, 'rb') as plain:
                        header = plain.read(8)

                if header == target_magic:
                    expected_entries.append((f, path))
            except Exception:
                pass

    return sorted(expected_entries)

def get_expected_files():
    return [name for name, _ in get_expected_entries()]

def test_archive_created_and_valid():
    config = get_config()
    archive_path = config.get("output_archive", "/home/user/verified_wals.tar.gz")

    assert os.path.exists(archive_path), f"Output archive missing at {archive_path}"
    assert tarfile.is_tarfile(archive_path), f"File at {archive_path} is not a valid tar archive"

    expected_entries = get_expected_entries()
    expected_files = [name for name, _ in expected_entries]

    with tarfile.open(archive_path, 'r:gz') as tar:
        members = tar.getnames()

        assert sorted(members) == expected_files, (
            f"Archive contents do not match expected files. "
            f"Expected: {expected_files}, Found: {sorted(members)}"
        )

        for name, source_path in expected_entries:
            member = tar.getmember(name)
            assert member.isfile(), f"Archived member {name} is not a regular file"
            archived_file = tar.extractfile(member)
            assert archived_file is not None, f"Could not read archived member {name}"
            archived_data = archived_file.read()
            with open(source_path, 'rb') as source_file:
                source_data = source_file.read()
            assert archived_data == source_data, (
                f"Archived member {name} does not contain the original on-disk file data"
            )

def test_log_file_contents():
    log_path = "/home/user/archive_log.txt"
    assert os.path.exists(log_path), f"Log file missing at {log_path}"

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_files = get_expected_files()

    assert lines == expected_files, (
        f"Log file contents do not match expected files or are not sorted properly. "
        f"Expected: {expected_files}, Found: {lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
