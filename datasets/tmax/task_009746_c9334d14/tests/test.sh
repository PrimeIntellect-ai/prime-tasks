#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import fcntl
import json
import os
import random
import re
import shutil
import stat
import string
import subprocess
import time

import pytest

SOURCE = "/home/user/backup_source"
MANIFEST = "/home/user/backup_manifest.json"
GENERATOR_SOURCE = "/home/user/manifest_generator.c"
GENERATOR = "/home/user/manifest_generator"
VERIFIED_GENERATOR = "/tmp/manifest_generator_verified"
ARCHIVE_SCRIPT = "/home/user/archive.sh"
ARCHIVE_DEST = "/home/user/archive_dest"

ORIGINAL_EXPECTED = [
    {"file_path": "/home/user/backup_source/db1/data.csv", "latest_id": 1050},
    {"file_path": "/home/user/backup_source/db1/old_data.csv", "latest_id": 999},
    {"file_path": "/home/user/backup_source/db2/logs/001.wal", "latest_id": 800},
    {"file_path": "/home/user/backup_source/db2/logs/002.wal", "latest_id": 2048},
]


def load_manifest():
    assert os.path.isfile(MANIFEST), f"Manifest file {MANIFEST} is missing."
    try:
        with open(MANIFEST, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Manifest file {MANIFEST} is not valid JSON.")
    assert isinstance(data, list), f"Manifest JSON in {MANIFEST} should be a list of objects."
    return data


def sorted_manifest(data):
    return sorted(data, key=lambda x: x.get("file_path", ""))


def derive_expected():
    expected = []
    for root, _, names in os.walk(SOURCE):
        for name in names:
            path = os.path.abspath(os.path.join(root, name))
            if name.endswith(".csv"):
                with open(path, newline="") as f:
                    rows = list(csv.DictReader(f))
                assert rows, f"Verifier CSV fixture unexpectedly has no rows: {path}"
                latest_id = int(rows[-1]["id"])
            elif name.endswith(".wal"):
                with open(path, "r") as f:
                    first = f.readline()
                match = re.fullmatch(r"TXN_ID: ([+-]?\d+)\s*", first)
                assert match, f"Verifier WAL fixture has an invalid first line: {path}"
                latest_id = int(match.group(1))
            else:
                continue
            expected.append({"file_path": path, "latest_id": latest_id})
    return sorted_manifest(expected)


def run_generator(path, timeout=10):
    result = subprocess.run([path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Generator {path} failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def run_archive():
    result = subprocess.run(["/bin/bash", ARCHIVE_SCRIPT], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0, (
        f"archive.sh failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def reset_archive():
    shutil.rmtree(ARCHIVE_DEST, ignore_errors=True)


def assert_original_archive():
    assert os.path.isdir(ARCHIVE_DEST), f"Archive destination directory {ARCHIVE_DEST} is missing."
    files = set(os.listdir(ARCHIVE_DEST))
    expected_files = {"data.csv", "002.wal"}
    assert files == expected_files, f"Archive directory contains {files}, expected exactly {expected_files}."

    with open("/home/user/backup_source/db1/data.csv", "r") as f:
        expected_data_csv = f.read()
    with open(os.path.join(ARCHIVE_DEST, "data.csv"), "r") as f:
        archived_data_csv = f.read()
    assert archived_data_csv == expected_data_csv, "Archived data.csv content does not match the source file."

    with open("/home/user/backup_source/db2/logs/002.wal", "r") as f:
        expected_002_wal = f.read()
    with open(os.path.join(ARCHIVE_DEST, "002.wal"), "r") as f:
        archived_002_wal = f.read()
    assert archived_002_wal == expected_002_wal, "Archived 002.wal content does not match the source file."


def lock_files(paths, operation):
    handles = []
    try:
        for path in paths:
            mode = "rb" if operation == fcntl.LOCK_SH else "r+b"
            handle = open(path, mode)
            fcntl.lockf(handle.fileno(), operation | fcntl.LOCK_NB)
            handles.append(handle)
        return handles
    except Exception:
        for handle in handles:
            handle.close()
        raise


def unlock_files(handles):
    for handle in handles:
        try:
            fcntl.lockf(handle.fileno(), fcntl.LOCK_UN)
        finally:
            handle.close()


def test_complete_submission():
    # Artifact and source checks, including the original source-level locking assertion.
    assert os.path.isfile(GENERATOR_SOURCE), f"C program file {GENERATOR_SOURCE} is missing."
    with open(GENERATOR_SOURCE, "r") as f:
        source_content = f.read()
    assert "fcntl" in source_content or "flock" in source_content, \
        "C program must use 'fcntl' or 'flock' locking mechanisms."

    assert os.path.isfile(GENERATOR), f"Executable {GENERATOR} is missing."
    assert os.access(GENERATOR, os.X_OK), f"{GENERATOR} is not executable."
    with open(GENERATOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{GENERATOR} is not a compiled ELF executable."
    assert os.path.isfile(ARCHIVE_SCRIPT), f"Archive script {ARCHIVE_SCRIPT} is missing."

    # Discard submitted output and execute both demanded artifacts from scratch.
    if os.path.exists(MANIFEST):
        os.remove(MANIFEST)
    reset_archive()
    run_generator(GENERATOR)

    data = load_manifest()
    assert sorted_manifest(data) == sorted_manifest(ORIGINAL_EXPECTED), \
        "Manifest content does not match the expected mappings."

    run_archive()
    assert_original_archive()

    # Compile the submitted source independently so behavior cannot be supplied only
    # by an unrelated prebuilt executable.
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", GENERATOR_SOURCE, "-o", VERIFIED_GENERATOR],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        f"manifest_generator.c did not compile.\nstdout:\n{compile_result.stdout}\n"
        f"stderr:\n{compile_result.stderr}"
    )

    token = "verify_" + "".join(random.SystemRandom().choices(string.ascii_lowercase + string.digits, k=12))
    dynamic_dir = os.path.join(SOURCE, token, "nested")
    os.makedirs(dynamic_dir)
    rng = random.SystemRandom()
    csv_id = rng.randint(3001, 900000)
    csv_old = rng.randint(1, 700)
    wal_id = rng.randint(3001, 900000)
    dynamic_csv = os.path.join(dynamic_dir, token + ".csv")
    dynamic_wal = os.path.join(dynamic_dir, token + ".wal")
    with open(dynamic_csv, "w") as f:
        f.write(f"id,data\n{csv_old},first\n{csv_id},last\n")
    with open(dynamic_wal, "w") as f:
        f.write(f"TXN_ID: {wal_id}\nDATA: randomized verifier record\n")
    with open(os.path.join(dynamic_dir, token + ".txt"), "w") as f:
        f.write("TXN_ID: 999999\n")

    try:
        expected_dynamic = derive_expected()

        # The required named executable must handle recursively discovered,
        # verification-time inputs rather than just the original fixtures.
        run_generator(GENERATOR)
        assert sorted_manifest(load_manifest()) == expected_dynamic, \
            "The named generator did not correctly process dynamic recursive inputs."

        eligible_paths = [entry["file_path"] for entry in expected_dynamic]

        # A shared POSIX lock held by another process must not prevent reading.
        shared_handles = lock_files(eligible_paths, fcntl.LOCK_SH)
        try:
            start = time.monotonic()
            run_generator(VERIFIED_GENERATOR, timeout=8)
            baseline = time.monotonic() - start
        finally:
            unlock_files(shared_handles)
        assert sorted_manifest(load_manifest()) == expected_dynamic, \
            "The generator produced incorrect output while compatible shared locks were held."

        # For every eligible file, an existing exclusive POSIX lock must make the
        # submitted program wait until that lock is released.
        wait_time = min(3.0, max(0.6, baseline * 4 + 0.25))
        for locked_path in eligible_paths:
            handles = lock_files([locked_path], fcntl.LOCK_EX)
            proc = subprocess.Popen([VERIFIED_GENERATOR], stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, text=True)
            try:
                time.sleep(wait_time)
                assert proc.poll() is None, (
                    f"Generator did not wait for a conflicting fcntl lock on {locked_path}."
                )
            finally:
                unlock_files(handles)
            stdout, stderr = proc.communicate(timeout=8)
            assert proc.returncode == 0, (
                f"Generator failed after the lock on {locked_path} was released.\n"
                f"stdout:\n{stdout}\nstderr:\n{stderr}"
            )
            assert sorted_manifest(load_manifest()) == expected_dynamic

        # Prove archive.sh reads and filters the manifest rather than copying a
        # hardcoded set or independently recomputing IDs.
        altered = []
        for entry in load_manifest():
            altered.append({"file_path": entry["file_path"], "latest_id": 0})
        chosen = next(x for x in altered if x["file_path"] == dynamic_wal)
        chosen["latest_id"] = rng.randint(1001, 900000)
        with open(MANIFEST, "w") as f:
            json.dump(altered, f)
        reset_archive()
        run_archive()
        assert os.path.isdir(ARCHIVE_DEST), f"Archive destination directory {ARCHIVE_DEST} is missing."
        assert set(os.listdir(ARCHIVE_DEST)) == {os.path.basename(dynamic_wal)}, \
            "archive.sh did not strictly filter the verification-time manifest."
        with open(dynamic_wal, "rb") as src, open(os.path.join(ARCHIVE_DEST, os.path.basename(dynamic_wal)), "rb") as dst:
            assert dst.read() == src.read(), "Dynamically selected archived file differs from its source."
    finally:
        shutil.rmtree(os.path.join(SOURCE, token), ignore_errors=True)

    # Restore and re-check the requested final state after removing verifier fixtures.
    run_generator(GENERATOR)
    assert sorted_manifest(load_manifest()) == sorted_manifest(ORIGINAL_EXPECTED), \
        "Manifest content does not match the expected mappings after re-execution."
    reset_archive()
    run_archive()
    assert_original_archive()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
