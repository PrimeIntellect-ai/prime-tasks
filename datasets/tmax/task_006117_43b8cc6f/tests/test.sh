#!/bin/bash
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
from datetime import datetime, timezone


def test_executable_exists():
    executable_path = "/home/user/cost_optimizer"
    assert os.path.isfile(executable_path), f"Executable missing: {executable_path}"
    assert os.access(executable_path, os.X_OK), f"File is not executable: {executable_path}"
    assert stat.S_ISREG(os.lstat(executable_path).st_mode), "Executable must be a regular file"
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cost_optimizer must be a compiled ELF executable"


def test_source_exists():
    source_path = "/home/user/cost_optimizer.cpp"
    assert os.path.isfile(source_path), f"Source code missing: {source_path}"
    assert stat.S_ISREG(os.lstat(source_path).st_mode), "Source must be a regular file"


def test_backup_files():
    backup_files = {
        "/home/user/storage_backup/large1.bin": 150000,
        "/home/user/storage_backup/large2.bin": 200000,
    }
    for f_path, expected_size in backup_files.items():
        assert os.path.isfile(f_path), f"Backup file missing: {f_path}"
        actual_size = os.path.getsize(f_path)
        assert actual_size == expected_size, f"Backup file {f_path} has incorrect size: {actual_size} != {expected_size}"


def test_staged_files():
    staged_files = {
        "/home/user/archive_staging/large1.bin": 150000,
        "/home/user/archive_staging/large2.bin": 200000,
    }
    for f_path, expected_size in staged_files.items():
        assert os.path.isfile(f_path), f"Staged file missing: {f_path}"
        actual_size = os.path.getsize(f_path)
        assert actual_size == expected_size, f"Staged file {f_path} has incorrect size: {actual_size} != {expected_size}"


def test_fixed_file_contents():
    for path in [
        "/home/user/storage_backup/large1.bin",
        "/home/user/storage_backup/large2.bin",
        "/home/user/archive_staging/large1.bin",
        "/home/user/archive_staging/large2.bin",
    ]:
        with open(path, "rb") as f:
            assert not f.read().strip(b"\0"), f"File content was not preserved: {path}"


def test_original_large_files_removed():
    removed_files = [
        "/home/user/cloud_storage/bucketA/large1.bin",
        "/home/user/cloud_storage/bucketB/large2.bin",
    ]
    for f_path in removed_files:
        assert not os.path.exists(f_path), f"Original large file should have been removed: {f_path}"


def test_original_small_files_remain():
    small_files = {
        "/home/user/cloud_storage/bucketA/small1.txt": 50000,
        "/home/user/cloud_storage/bucketB/small2.txt": 99999,
    }
    for f_path, expected_size in small_files.items():
        assert os.path.isfile(f_path), f"Small file should still exist: {f_path}"
        actual_size = os.path.getsize(f_path)
        assert actual_size == expected_size, f"Small file {f_path} has incorrect size: {actual_size} != {expected_size}"


def test_audit_log():
    log_path = "/home/user/finops_audit.log"
    assert os.path.isfile(log_path), f"Audit log missing: {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Audit log should contain exactly 2 lines, found {len(lines)}"

    pattern1 = r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) UTC\] STAGED \/home\/user\/cloud_storage\/bucketA\/large1\.bin 150000 bytes$"
    pattern2 = r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) UTC\] STAGED \/home\/user\/cloud_storage\/bucketB\/large2\.bin 200000 bytes$"

    matches1 = [re.match(pattern1, line) for line in lines]
    matches2 = [re.match(pattern2, line) for line in lines]
    matches = [m for m in matches1 + matches2 if m]

    assert any(matches1), "Audit log missing or incorrect format for large1.bin entry"
    assert any(matches2), "Audit log missing or incorrect format for large2.bin entry"

    now = datetime.now(timezone.utc)
    for match in matches:
        timestamp = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        assert abs((now - timestamp).total_seconds()) < 86400, "Audit timestamp is not current UTC time"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

if [ "$status" -eq 0 ]; then
python3 << 'BEHAVIOR_EOF' || status=1
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
from datetime import datetime, timedelta, timezone

HOME = "/home/user"
CONFIG = f"{HOME}/storage_config.txt"
BACKUP = f"{HOME}/storage_backup"
STAGING = f"{HOME}/archive_staging"
LOG = f"{HOME}/finops_audit.log"
EXE = f"{HOME}/cost_optimizer"
SOURCE = f"{HOME}/cost_optimizer.cpp"

work = tempfile.mkdtemp(prefix="costopt_verifier_", dir="/tmp")
test_root = tempfile.mkdtemp(prefix="costopt_input_", dir=HOME)
saved_backup = os.path.join(work, "original_backup")
saved_staging = os.path.join(work, "original_staging")
saved_log = os.path.join(work, "original_log")
compiled = os.path.join(work, "compiled_from_source")
with open(CONFIG, "rb") as f:
    original_config = f.read()
config_mode = stat.S_IMODE(os.stat(CONFIG).st_mode)


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


try:
    # Confirm the submitted source really is valid C++17 source.
    subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", compiled],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )

    os.rename(BACKUP, saved_backup)
    os.rename(STAGING, saved_staging)
    os.rename(LOG, saved_log)

    token = uuid.uuid4().hex
    bucket1 = os.path.join(test_root, "bucket_" + token[:8])
    bucket2 = os.path.join(test_root, "bucket_" + token[8:16])
    missing = os.path.join(test_root, "missing_" + token[16:24])
    nested = os.path.join(bucket1, "nested")
    os.makedirs(nested)
    os.makedirs(bucket2)

    large1_name = "large_" + token[:12] + ".bin"
    large2_name = "large_" + token[12:24] + ".dat"
    boundary_name = "boundary_" + token[24:] + ".bin"
    small_name = "small_" + token[:10] + ".txt"
    nested_name = "nested_" + token[10:22] + ".bin"

    large1_path = os.path.join(bucket1, large1_name)
    large2_path = os.path.join(bucket2, large2_name)
    boundary_path = os.path.join(bucket1, boundary_name)
    small_path = os.path.join(bucket2, small_name)
    nested_path = os.path.join(nested, nested_name)

    expected = {
        large1_path: os.urandom(100001),
        large2_path: os.urandom(131337),
    }
    boundary_data = os.urandom(100000)
    small_data = os.urandom(7919)
    nested_data = os.urandom(120003)

    for path, data in expected.items():
        with open(path, "wb") as f:
            f.write(data)
    with open(boundary_path, "wb") as f:
        f.write(boundary_data)
    with open(small_path, "wb") as f:
        f.write(small_data)
    with open(nested_path, "wb") as f:
        f.write(nested_data)

    with open(CONFIG, "w") as f:
        f.write(bucket1 + "\n")
        f.write(missing + "\n")
        f.write(bucket2 + "\n")

    # Verify append behavior while making the dynamically generated entries easy to isolate.
    seed = "PREEXISTING-AUDIT-LINE-" + token
    with open(LOG, "w") as f:
        f.write(seed + "\n")

    start = datetime.now(timezone.utc) - timedelta(seconds=2)
    env = os.environ.copy()
    env["TZ"] = "Pacific/Honolulu"
    env["LC_ALL"] = "C"
    subprocess.run(
        [EXE],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        env=env,
    )
    end = datetime.now(timezone.utc) + timedelta(seconds=2)

    assert os.path.isdir(BACKUP) and not os.path.islink(BACKUP), "Program did not create the backup directory"
    assert os.path.isdir(STAGING) and not os.path.islink(STAGING), "Program did not create the staging directory"

    for original, data in expected.items():
        name = os.path.basename(original)
        backup_path = os.path.join(BACKUP, name)
        staged_path = os.path.join(STAGING, name)
        assert not os.path.exists(original), f"Large original was not moved: {original}"
        assert os.path.isfile(backup_path), f"Dynamic backup missing: {backup_path}"
        assert os.path.isfile(staged_path), f"Dynamic staged file missing: {staged_path}"
        with open(backup_path, "rb") as f:
            assert f.read() == data, f"Backup content differs from source: {name}"
        with open(staged_path, "rb") as f:
            assert f.read() == data, f"Staged content differs from source: {name}"

    with open(boundary_path, "rb") as f:
        assert f.read() == boundary_data, "A file of exactly 100000 bytes was incorrectly processed"
    with open(small_path, "rb") as f:
        assert f.read() == small_data, "A small file was incorrectly processed"
    with open(nested_path, "rb") as f:
        assert f.read() == nested_data, "A nested file was incorrectly processed recursively"

    for name in (boundary_name, small_name, nested_name):
        assert not os.path.exists(os.path.join(BACKUP, name)), f"Ineligible file was backed up: {name}"
        assert not os.path.exists(os.path.join(STAGING, name)), f"Ineligible file was staged: {name}"

    with open(LOG, "r") as f:
        lines = [line.rstrip("\n") for line in f]
    assert lines.count(seed) == 1, "Audit log was overwritten instead of appended"
    staged_lines = [line for line in lines if line != seed]
    assert len(staged_lines) == 2, f"Expected exactly two dynamic audit entries, got {len(staged_lines)}"

    for original, data in expected.items():
        pattern = r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) UTC\] STAGED " + re.escape(original) + r" " + str(len(data)) + r" bytes$"
        matches = [re.match(pattern, line) for line in staged_lines]
        matches = [m for m in matches if m]
        assert len(matches) == 1, f"Missing or malformed dynamic audit entry for {original}"
        timestamp = datetime.strptime(matches[0].group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        assert start <= timestamp <= end, f"Audit timestamp is not the current UTC time for {original}"
finally:
    try:
        with open(CONFIG, "wb") as f:
            f.write(original_config)
        os.chmod(CONFIG, config_mode)
    except Exception:
        pass
    for path in (BACKUP, STAGING, LOG):
        try:
            remove_path(path)
        except Exception:
            pass
    for saved, destination in ((saved_backup, BACKUP), (saved_staging, STAGING), (saved_log, LOG)):
        try:
            if os.path.lexists(saved):
                os.rename(saved, destination)
        except Exception:
            pass
    shutil.rmtree(test_root, ignore_errors=True)
    shutil.rmtree(work, ignore_errors=True)
BEHAVIOR_EOF
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
