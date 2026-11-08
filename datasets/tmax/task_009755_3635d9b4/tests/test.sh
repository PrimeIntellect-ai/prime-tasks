#!/bin/bash
mkdir -p /logs/verifier

cat << 'CHALLENGE_EOF' > /tmp/test_dynamic_execution.py
import hashlib
import os
import secrets
import shutil
import stat
import subprocess
import tarfile

APP_DATA_DIR = "/home/user/app_data"
SCRIPT_PATH = "/home/user/archive_logs.py"
MANIFEST_PATH = "/home/user/manifest.txt"
TAR_PATH = "/home/user/clean_logs.tar"

assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist or is not a regular file."

challenge_dir = os.path.join(APP_DATA_DIR, ".verifier_" + secrets.token_hex(8))
os.makedirs(os.path.join(challenge_dir, "nested"))
challenge_log = os.path.join(challenge_dir, "nested", secrets.token_hex(6) + ".log")
with open(challenge_log, "wb") as f:
    f.write(os.urandom(173) + b"\nverifier dynamic log\n")
with open(os.path.join(challenge_dir, "not_a_log.bin"), "wb") as f:
    f.write(os.urandom(41))
os.symlink(challenge_log, os.path.join(challenge_dir, "ignored_symlink.log"))
os.symlink(challenge_dir, os.path.join(challenge_dir, "nested", "circular_dir"))

try:
    for path in (MANIFEST_PATH, TAR_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run(["python3", SCRIPT_PATH], check=True, timeout=20)

    expected_files = []
    for root, dirs, files in os.walk(APP_DATA_DIR, followlinks=False):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        for name in files:
            path = os.path.abspath(os.path.join(root, name))
            if not name.endswith(".log") or os.path.islink(path):
                continue
            if stat.S_ISREG(os.lstat(path).st_mode):
                expected_files.append(path)
    expected_files.sort()

    expected_lines = []
    for path in expected_files:
        with open(path, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        expected_lines.append(f"{digest} {path}\n")

    assert os.path.isfile(MANIFEST_PATH), "The executed script did not create a regular manifest file."
    with open(MANIFEST_PATH, "r") as f:
        assert f.readlines() == expected_lines, "Dynamic manifest contents are incorrect."

    assert os.path.isfile(TAR_PATH), "The executed script did not create a regular tar archive."
    with tarfile.open(TAR_PATH, "r:") as tar:
        members = tar.getmembers()
        assert [m.name for m in members] == expected_files, "Dynamic tar member names are incorrect."
        for member, source_path in zip(members, expected_files):
            assert member.isfile(), f"Tar member {member.name} is not a regular file."
            archived = tar.extractfile(member)
            assert archived is not None
            with archived, open(source_path, "rb") as source:
                assert archived.read() == source.read(), f"Tar member {member.name} does not match its source file."
finally:
    shutil.rmtree(challenge_dir, ignore_errors=True)
CHALLENGE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import tarfile
import pytest

APP_DATA_DIR = "/home/user/app_data"
SCRIPT_PATH = "/home/user/archive_logs.py"
MANIFEST_PATH = "/home/user/manifest.txt"
TAR_PATH = "/home/user/clean_logs.tar"

def get_expected_log_files():
    # These are the regular .log files created in the setup
    return [
        f"{APP_DATA_DIR}/module_a/access.log",
        f"{APP_DATA_DIR}/module_a/error.log",
        f"{APP_DATA_DIR}/module_b/nested/deep.log",
        f"{APP_DATA_DIR}/module_b/system.log",
    ]

def compute_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist or is not a regular file."

def test_manifest_exists_and_correct():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist or is not a regular file."

    expected_files = sorted(get_expected_log_files())
    expected_lines = []
    for f in expected_files:
        assert os.path.isfile(f), f"Expected log file {f} is missing from the filesystem."
        h = compute_sha256(f)
        expected_lines.append(f"{h} {f}\n")

    with open(MANIFEST_PATH, "r") as f:
        actual_lines = f.readlines()

    assert len(actual_lines) == len(expected_lines), f"Manifest has {len(actual_lines)} lines, expected {len(expected_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Manifest line {i+1} mismatch. Expected: {expected.strip()}, Actual: {actual.strip()}"

def test_tar_archive_exists_and_correct():
    assert os.path.isfile(TAR_PATH), f"Tar archive {TAR_PATH} does not exist or is not a regular file."

    expected_files = sorted(get_expected_log_files())

    try:
        with tarfile.open(TAR_PATH, "r") as tar:
            tar_members = tar.getnames()
    except tarfile.TarError as e:
        pytest.fail(f"Failed to read tar archive {TAR_PATH}: {e}")

    actual_files = sorted(tar_members)

    assert actual_files == expected_files, f"Tar archive contents mismatch.\nExpected: {expected_files}\nActual: {actual_files}"

    try:
        with tarfile.open(TAR_PATH, "r:") as tar:
            members = tar.getmembers()
            for member in members:
                assert member.isfile(), f"Tar member {member.name} is not a regular file."
                archived = tar.extractfile(member)
                assert archived is not None, f"Could not read tar member {member.name}."
                with archived, open(member.name, "rb") as source:
                    assert archived.read() == source.read(), f"Tar member {member.name} does not match its source log file."
    except tarfile.TarError as e:
        pytest.fail(f"Archive is not a valid uncompressed tar file: {e}")
TEST_EOF

result=0
python3 /tmp/test_dynamic_execution.py || result=1

rm -f /home/user/manifest.txt /home/user/clean_logs.tar
if [ -f /home/user/archive_logs.py ]; then
    timeout 20s python3 /home/user/archive_logs.py || result=1
else
    result=1
fi

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || result=1

if [ "$result" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
