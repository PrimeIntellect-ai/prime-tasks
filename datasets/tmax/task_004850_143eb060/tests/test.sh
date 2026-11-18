#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

def get_sha256(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()

def test_incremental_backup_files():
    v1_dir = "/home/user/configs_v1"
    v2_dir = "/home/user/configs_v2"
    backup_dir = "/home/user/incremental_backup"

    assert os.path.isdir(backup_dir), f"Backup directory {backup_dir} does not exist."

    for root, _, files in os.walk(v2_dir):
        for file in files:
            v2_path = os.path.join(root, file)
            rel_path = os.path.relpath(v2_path, v2_dir)
            v1_path = os.path.join(v1_dir, rel_path)

            v2_hash = get_sha256(v2_path)

            is_new = not os.path.exists(v1_path)
            is_modified = not is_new and get_sha256(v1_path) != v2_hash

            if is_new or is_modified:
                name, ext = os.path.splitext(file)
                new_name = f"{name}_{v2_hash[:8]}{ext}"
                backup_path = os.path.join(backup_dir, os.path.dirname(rel_path), new_name)

                assert os.path.isfile(backup_path), f"Expected backup file missing: {backup_path}"
                assert get_sha256(backup_path) == v2_hash, f"Content mismatch in backup file: {backup_path}"

def test_changes_log():
    v1_dir = "/home/user/configs_v1"
    v2_dir = "/home/user/configs_v2"
    log_file = "/home/user/changes.log"

    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    expected_lines = []

    for root, _, files in os.walk(v2_dir):
        for file in files:
            v2_path = os.path.join(root, file)
            rel_path = os.path.relpath(v2_path, v2_dir)
            v1_path = os.path.join(v1_dir, rel_path)

            v2_hash = get_sha256(v2_path)

            is_new = not os.path.exists(v1_path)
            is_modified = not is_new and get_sha256(v1_path) != v2_hash

            if is_new or is_modified:
                status = "NEW" if is_new else "MODIFIED"
                name, ext = os.path.splitext(file)
                new_name = f"{name}_{v2_hash[:8]}{ext}"

                # Ensure forward slashes for relative paths in log
                rel_path_fwd = rel_path.replace("\\", "/")
                dest_rel_path = os.path.join(os.path.dirname(rel_path), new_name).replace("\\", "/")
                if dest_rel_path.startswith("./"):
                    dest_rel_path = dest_rel_path[2:]

                line = f"[{status}] {rel_path_fwd} -> {dest_rel_path}"
                expected_lines.append(line)

    expected_lines.sort()

    with open(log_file, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"The {log_file} file contents do not match the expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )
TEST_EOF

verify() {
    test -f /home/user/tracker.py
    test ! -L /home/user/tracker.py

    case_id="verifier_case_$(cat /proc/sys/kernel/random/uuid)"
    mkdir -p "/home/user/configs_v1/$case_id/nested" "/home/user/configs_v2/$case_id/nested"
    printf 'old-%s\n' "$case_id" > "/home/user/configs_v1/$case_id/nested/modified.settings.ini"
    printf 'new-%s\n' "$case_id" > "/home/user/configs_v2/$case_id/nested/modified.settings.ini"
    printf 'added-%s\n' "$case_id" > "/home/user/configs_v2/$case_id/nested/new.conf"
    printf 'unchanged-%s\n' "$case_id" > "/home/user/configs_v1/$case_id/unchanged.conf"
    printf 'unchanged-%s\n' "$case_id" > "/home/user/configs_v2/$case_id/unchanged.conf"

    rm -rf /home/user/incremental_backup
    rm -f /home/user/changes.log

    (cd /home/user && python3 /home/user/tracker.py)
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
