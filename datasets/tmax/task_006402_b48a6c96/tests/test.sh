#!/bin/bash
mkdir -p /logs/verifier
reward=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import stat
import subprocess

import pytest

EXPECTED_SUCCESS_LOG = """System Check: OK
--- BACKUP START ---
Timestamp: 2023-10-24T10:00:00Z
Status: SUCCESS
Message: Backup completed with status SUCCESS
--- BACKUP END ---
Cleanup: DONE
"""

EXPECTED_FAILED_LOG = """System Check: OK
--- BACKUP START ---
Timestamp: 2023-10-24T10:00:00Z
Status: FAILED
Message: Backup completed with status FAILED
--- BACKUP END ---
Cleanup: DONE
"""

with open('/tmp/dedup_expected.json', encoding='utf-8') as f:
    EXPECTED = json.load(f)


def get_build_id(filepath):
    """Helper to extract the GNU Build ID using readelf."""
    try:
        output = subprocess.check_output(['readelf', '-n', filepath], universal_newlines=True)
        for line in output.splitlines():
            if "Build ID" in line:
                return line.split()[-1].strip()
    except Exception as e:
        pytest.fail(f"Failed to extract Build ID from {filepath}: {e}")
    return None


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def assert_regular_file(path):
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"{path} is not a regular file"


def assert_expected_binary(path, reference_name):
    assert_regular_file(path)
    assert sha256_file(path) == EXPECTED[reference_name]['sha256'], \
        f"{path} does not contain the expected {reference_name} ELF data"
    assert get_build_id(path) == EXPECTED[reference_name]['build_id'], \
        f"{path} has the wrong GNU Build ID"


def same_inode(path_a, path_b):
    a = os.stat(path_a)
    b = os.stat(path_b)
    return (a.st_dev, a.st_ino) == (b.st_dev, b.st_ino)


def test_directories_extracted():
    assert os.path.isdir("/home/user/extracted/app_v1"), "app_v1 was not extracted"
    assert os.path.isdir("/home/user/extracted/app_v2"), "app_v2 was not extracted"
    assert not os.path.isdir("/home/user/extracted/app_v3"), "app_v3 should have been skipped due to corruption"
    assert not os.path.lexists("/home/user/extracted/app_v3"), "corrupt app_v3 left an extraction artifact"
    assert os.path.isdir("/home/user/extracted/app_v4"), "app_v4 was not extracted"


def test_logs_were_extracted_correctly():
    logs = {
        "/home/user/extracted/app_v1/app_v1/backup.log": EXPECTED_SUCCESS_LOG,
        "/home/user/extracted/app_v2/app_v2/backup.log": EXPECTED_SUCCESS_LOG,
        "/home/user/extracted/app_v4/app_v4/backup.log": EXPECTED_FAILED_LOG,
    }
    for path, expected in logs.items():
        assert_regular_file(path)
        with open(path, encoding='utf-8') as f:
            assert f.read() == expected, f"Extracted log content is incorrect: {path}"


def test_log_symlinks():
    link_v1 = "/home/user/log_links/app_v1_backup.log"
    link_v2 = "/home/user/log_links/app_v2_backup.log"
    link_v4 = "/home/user/log_links/app_v4_backup.log"

    assert os.path.islink(link_v1), f"{link_v1} is missing or not a symlink"
    assert os.path.islink(link_v2), f"{link_v2} is missing or not a symlink"
    assert not os.path.islink(link_v4), f"{link_v4} should not exist (FAILED status)"
    assert not os.path.lexists(link_v4), f"{link_v4} should not exist (FAILED status)"

    target_v1 = os.readlink(link_v1)
    target_v2 = os.readlink(link_v2)

    assert target_v1 == "/home/user/extracted/app_v1/app_v1/backup.log", f"Symlink target for v1 is incorrect: {target_v1}"
    assert target_v2 == "/home/user/extracted/app_v2/app_v2/backup.log", f"Symlink target for v2 is incorrect: {target_v2}"
    assert os.path.isfile(link_v1), f"{link_v1} is dangling"
    assert os.path.isfile(link_v2), f"{link_v2} is dangling"


def test_elf_deduplication():
    id_ls = get_build_id("/bin/ls")
    id_cat = get_build_id("/bin/cat")
    id_echo = get_build_id("/bin/echo")

    assert id_ls, "Could not get Build ID for /bin/ls"
    assert id_cat, "Could not get Build ID for /bin/cat"
    assert id_echo, "Could not get Build ID for /bin/echo"
    assert id_ls == EXPECTED['ls']['build_id']
    assert id_cat == EXPECTED['cat']['build_id']
    assert id_echo == EXPECTED['echo']['build_id']

    master_ls = f"/home/user/elf_master/{id_ls}.elf"
    master_cat = f"/home/user/elf_master/{id_cat}.elf"
    master_echo = f"/home/user/elf_master/{id_echo}.elf"

    assert os.path.isfile(master_ls), f"Master ELF for ls ({master_ls}) is missing"
    assert os.path.isfile(master_cat), f"Master ELF for cat ({master_cat}) is missing"
    assert os.path.isfile(master_echo), f"Master ELF for echo ({master_echo}) is missing"

    assert_expected_binary(master_ls, 'ls')
    assert_expected_binary(master_cat, 'cat')
    assert_expected_binary(master_echo, 'echo')

    v1_app = "/home/user/extracted/app_v1/app_v1/bin/app"
    v2_app = "/home/user/extracted/app_v2/app_v2/bin/app"
    v1_cat = "/home/user/extracted/app_v1/app_v1/bin/helper"
    v2_echo = "/home/user/extracted/app_v2/app_v2/bin/tool"
    v4_app = "/home/user/extracted/app_v4/app_v4/bin/app"

    assert_expected_binary(v1_app, 'ls')
    assert_expected_binary(v2_app, 'ls')
    assert_expected_binary(v1_cat, 'cat')
    assert_expected_binary(v2_echo, 'echo')
    assert_expected_binary(v4_app, 'cat')

    inode_master_ls = os.stat(master_ls).st_ino
    inode_v1_app = os.stat(v1_app).st_ino
    inode_v2_app = os.stat(v2_app).st_ino

    assert inode_master_ls == inode_v1_app, "Hardlink for app_v1 bin/app (ls) does not match master"
    assert inode_master_ls == inode_v2_app, "Hardlink for app_v2 bin/app (ls) does not match master"
    assert same_inode(master_ls, v1_app)
    assert same_inode(master_ls, v2_app)

    inode_master_cat = os.stat(master_cat).st_ino
    inode_v1_cat = os.stat(v1_cat).st_ino

    assert inode_master_cat == inode_v1_cat, "Hardlink for app_v1 bin/helper (cat) does not match master"
    assert same_inode(master_cat, v1_cat)
    assert same_inode(master_echo, v2_echo), "Hardlink for app_v2 bin/tool (echo) does not match master"

    inode_v4_app = os.stat(v4_app).st_ino
    assert inode_master_cat != inode_v4_app, "Failed backup (app_v4) was incorrectly deduplicated"
    assert not same_inode(master_cat, v4_app), "Failed backup (app_v4) was incorrectly deduplicated"
TEST_EOF

# Capture the expected ELF identities and contents before executing the submission.
if python3 - << 'PY'
import hashlib
import json
import subprocess

result = {}
for name, path in [('ls', '/bin/ls'), ('cat', '/bin/cat'), ('echo', '/bin/echo')]:
    output = subprocess.check_output(['readelf', '-n', path], text=True)
    build_id = None
    for line in output.splitlines():
        if 'Build ID' in line:
            build_id = line.split()[-1].strip()
            break
    if not build_id:
        raise RuntimeError(f'No Build ID for {path}')
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            digest.update(chunk)
    result[name] = {'build_id': build_id, 'sha256': digest.hexdigest()}
with open('/tmp/dedup_expected.json', 'w', encoding='utf-8') as f:
    json.dump(result, f)
PY
then
    if [ -f /home/user/workspace/dedup.go ] && [ ! -L /home/user/workspace/dedup.go ] && \
       go build -o /tmp/dedup_submission /home/user/workspace/dedup.go; then
        rm -rf /home/user/extracted /home/user/elf_master /home/user/log_links
        mkdir -p /home/user/extracted /home/user/elf_master /home/user/log_links
        chmod 777 /home/user/extracted /home/user/elf_master /home/user/log_links

        if timeout 60s runuser -u user -- env HOME=/home/user /tmp/dedup_submission; then
            if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
                reward=1
            fi
        fi
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
