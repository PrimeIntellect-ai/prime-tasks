#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import hashlib
import os
import secrets
import stat
import subprocess
import uuid

import pytest


def test_auto_restore_expect_script():
    expect_script = "/home/user/auto_restore.exp"
    cli_script = "/app/microservices/cli_admin.py"
    assert os.path.exists(expect_script), f"Expect script not found at {expect_script}"
    assert os.path.isfile(expect_script), f"Expect script is not a regular file: {expect_script}"
    assert os.path.isfile(cli_script), f"CLI tool not found at {cli_script}"

    # Temporarily instrument the real CLI so merely printing its success message
    # cannot pass: successful interaction with this exact path creates a nonce.
    marker = f"/tmp/restore_invoked_{uuid.uuid4().hex}"
    token = secrets.token_hex(32)
    with open(cli_script, "rb") as f:
        original_cli = f.read()
    original_mode = stat.S_IMODE(os.stat(cli_script).st_mode)

    instrumented_cli = f'''#!/usr/bin/env python3
import sys
pwd = input("Enter admin password: ")
if pwd != "admin123":
    print("Invalid password")
    sys.exit(1)
confirm = input("Confirm restore? (y/n): ")
if confirm.lower() != 'y':
    print("Aborted")
    sys.exit(1)
with open({marker!r}, "w") as marker_file:
    marker_file.write({token!r})
print("Restore successful")
sys.exit(0)
'''

    try:
        with open(cli_script, "w") as f:
            f.write(instrumented_cli)
        os.chmod(cli_script, original_mode)

        try:
            res = subprocess.run(
                ["expect", expect_script], capture_output=True, text=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Expect script timed out after 5 seconds.")

        assert res.returncode == 0, (
            f"Expect script failed with return code {res.returncode}. "
            f"Output: {res.stdout}\nError: {res.stderr}"
        )
        assert "Restore successful" in res.stdout, (
            f"Restore CLI did not succeed. Output: {res.stdout}"
        )
        assert os.path.isfile(marker), (
            "Expect script did not successfully interact with "
            "/app/microservices/cli_admin.py"
        )
        with open(marker) as f:
            assert f.read() == token, "CLI invocation marker was invalid"
    finally:
        with open(cli_script, "wb") as f:
            f.write(original_cli)
        os.chmod(cli_script, original_mode)
        if os.path.exists(marker):
            os.remove(marker)


def test_backup_service_performance_and_correctness():
    raw_dir = "/home/user/data/raw"
    backup_dir = "/home/user/data/backup"

    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(backup_dir, exist_ok=True)

    # Clean up directories first
    for f in glob.glob(os.path.join(raw_dir, "*")):
        os.remove(f)
    for f in glob.glob(os.path.join(backup_dir, "*")):
        os.remove(f)

    # Generate 5000 files. Each keeps the original 140-byte size, but contains
    # per-run/per-file data so fabricated precomputed archives cannot pass.
    nonce = secrets.token_bytes(32)
    base_content = b"DUMMY LOG DATA" * 10
    expected = {}
    for i in range(5000):
        filename = f"file_{i}.txt"
        prefix = hashlib.sha256(nonce + str(i).encode()).digest()[:16]
        content = prefix + base_content[16:]
        expected[filename + ".gz"] = content
        with open(os.path.join(raw_dir, filename), "wb") as f:
            f.write(content)

    # Check that backup script exists
    backup_script = "/home/user/backup_service.py"
    assert os.path.exists(backup_script), f"Backup script not found at {backup_script}"
    assert os.path.isfile(backup_script), f"Backup script is not a regular file: {backup_script}"

    # Run the backup service
    start_time = __import__("time").time()
    res = subprocess.run(["python3", backup_script], capture_output=True, text=True)
    duration = __import__("time").time() - start_time

    assert res.returncode == 0, (
        f"Backup service failed with return code {res.returncode}. Error: {res.stderr}"
    )

    raw_files = glob.glob(os.path.join(raw_dir, "*"))
    backup_files = glob.glob(os.path.join(backup_dir, "*.gz"))

    assert len(raw_files) == 0, f"Raw directory not empty, found {len(raw_files)} files."
    assert len(backup_files) == 5000, (
        f"Backup directory missing files, found {len(backup_files)} files."
    )
    assert duration <= 2.0, (
        f"Performance threshold failed. Time taken: {duration:.2f}s (Threshold: 2.0s)"
    )

    actual_names = {os.path.basename(path) for path in backup_files}
    assert actual_names == set(expected), "Backup filenames do not match the input filenames"

    # Every output must be a valid gzip stream containing the corresponding
    # input bytes, not merely an empty or invalid file with a .gz suffix.
    for path in backup_files:
        name = os.path.basename(path)
        try:
            with gzip.open(path, "rb") as f:
                restored = f.read()
        except (OSError, EOFError) as exc:
            pytest.fail(f"Invalid gzip archive {name}: {exc}")
        assert restored == expected[name], f"Incorrect decompressed content in {name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
