#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import pytest

def test_dataset_snapshot_exists():
    """Check if the dataset_snapshot directory was created."""
    snapshot_dir = "/home/user/dataset_snapshot"
    assert os.path.isdir(snapshot_dir), f"Directory {snapshot_dir} does not exist."

def test_hard_links_created():
    """Verify that hard links were created for all files in live_dataset."""
    live_dir = "/home/user/live_dataset"
    snapshot_dir = "/home/user/dataset_snapshot"

    files = ["data1.csv", "data2.csv", "data3.csv"]
    for filename in files:
        live_file = os.path.join(live_dir, filename)
        snap_file = os.path.join(snapshot_dir, filename)

        assert os.path.isfile(snap_file), f"File {snap_file} is missing in snapshot directory."

        live_inode = os.stat(live_file).st_ino
        snap_inode = os.stat(snap_file).st_ino

        assert live_inode == snap_inode, f"{snap_file} is not a hard link to {live_file}."

def test_inc_backup_archive():
    """Verify the incremental backup archive contains the correct files and snapshot contents."""
    inc_backup = "/home/user/backups/inc_backup.tar.gz"
    snapshot_dir = "/home/user/dataset_snapshot"
    assert os.path.isfile(inc_backup), f"Archive {inc_backup} does not exist."

    with tarfile.open(inc_backup, "r:gz") as tar:
        members = tar.getnames()

        expected_members = {"data1.csv", "data3.csv"}
        assert set(members) == expected_members, f"Archive contents {members} do not match expected {expected_members}."

        for member in tar.getmembers():
            assert member.isfile(), f"Archive member {member.name} is not a regular file."
            archived_file = tar.extractfile(member)
            assert archived_file is not None, f"Could not read archive member {member.name}."
            archived_content = archived_file.read()

            snapshot_path = os.path.join(snapshot_dir, member.name)
            with open(snapshot_path, "rb") as f:
                snapshot_content = f.read()

            assert archived_content == snapshot_content, (
                f"Archive member {member.name} does not match the snapshot file."
            )

def test_verify_log():
    """Verify the verify.log file contains the expected sorted output."""
    verify_log = "/home/user/backups/verify.log"
    assert os.path.isfile(verify_log), f"Log file {verify_log} does not exist."

    with open(verify_log, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = ["data1.csv", "data3.csv"]
    assert content == expected_content, f"verify.log contents {content} do not match expected {expected_content}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
