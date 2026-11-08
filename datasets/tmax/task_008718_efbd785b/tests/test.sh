#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

import pytest

SCRIPT_PATH = Path("/home/user/sanitize_archive.py")
SOURCE_PATH = Path("/home/user/backups/app_logs.tar.gz")
OUTPUT_PATH = Path("/home/user/backups/sanitized_app_logs.tar.gz")
REPORT_PATH = Path("/home/user/backups/report.txt")
EXPECTED_CONTENTS = {}
EXPECTED_REMOVED = 0


def remove_path(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    global EXPECTED_CONTENTS, EXPECTED_REMOVED

    assert SCRIPT_PATH.is_file(), "/home/user/sanitize_archive.py is missing."

    # Replace the input with a fresh archive whose preserved content cannot be
    # satisfied by a prebuilt or hardcoded sanitized archive. It has the same
    # filenames, size profile, and leak count as the task's original input.
    nonce = secrets.token_hex(16)
    leak_counts = {1: 2, 2: 1, 3: 0, 4: 1, 5: 10}
    expected = {}
    removed = 0

    SOURCE_PATH.parent.mkdir(parents=True, exist_ok=True)
    remove_path(SOURCE_PATH)
    with tarfile.open(SOURCE_PATH, "w:gz") as tar:
        for i in range(1, 6):
            filename = f"service_{i}.log"
            normal_lines = [
                f"INFO: Normal log entry {j} [{nonce}:{i}]\n"
                for j in range(1, 101)
            ]
            leak_lines = [
                f"CREDENTIAL_LEAK: {nonce}_service_{i}_leak_{j}\n"
                for j in range(1, leak_counts[i] + 1)
            ]
            original_data = "".join(normal_lines + leak_lines).encode("utf-8")
            sanitized_data = b"".join(
                line for line in original_data.splitlines(keepends=True)
                if not line.startswith(b"CREDENTIAL_LEAK:")
            )
            expected[filename] = sanitized_data
            removed += leak_counts[i]

            info = tarfile.TarInfo(filename)
            info.size = len(original_data)
            info.mode = 0o644
            tar.addfile(info, io.BytesIO(original_data))

    assert removed == 14
    EXPECTED_CONTENTS = expected
    EXPECTED_REMOVED = removed

    remove_path(OUTPUT_PATH)
    remove_path(REPORT_PATH)

    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"sanitize_archive.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_script_exists():
    assert os.path.isfile("/home/user/sanitize_archive.py"), "/home/user/sanitize_archive.py is missing."


def test_report_file():
    report_path = "/home/user/backups/report.txt"
    assert os.path.isfile(report_path), f"{report_path} is missing."

    with open(report_path, "r") as f:
        content = f.read().strip()

    assert EXPECTED_REMOVED == 14
    assert content == "Removed: 14 lines", f"Expected report.txt to contain 'Removed: 14 lines', but got '{content}'."


def test_sanitized_archive_exists_and_valid():
    archive_path = "/home/user/backups/sanitized_app_logs.tar.gz"
    assert os.path.isfile(archive_path), f"{archive_path} is missing."

    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            members = tar.getmembers()
            filenames = [m.name for m in members]

            # Retain the original filename assertion.
            expected_filenames = {f"service_{i}.log" for i in range(1, 6)}
            actual_filenames = set(filenames)
            assert expected_filenames.issubset(actual_filenames), f"Archive is missing some expected log files. Found: {filenames}"

            # The output must contain exactly one regular file for every input
            # file, with every non-sensitive byte preserved.
            regular_members = [m for m in members if m.isfile()]
            assert len(regular_members) == 5, f"Expected exactly 5 regular files, found {[m.name for m in regular_members]}"
            assert {m.name for m in regular_members} == expected_filenames, f"Unexpected archive filenames: {filenames}"

            total_leaks = 0
            for member in regular_members:
                f = tar.extractfile(member)
                assert f is not None, f"Could not read {member.name}"
                data = f.read()
                assert data == EXPECTED_CONTENTS[member.name], (
                    f"Non-sensitive log content was not preserved exactly in {member.name}."
                )
                lines = data.decode("utf-8").splitlines()
                total_leaks += sum(1 for line in lines if line.startswith("CREDENTIAL_LEAK:"))

            assert total_leaks == 0, f"Found {total_leaks} CREDENTIAL_LEAK lines in the sanitized archive. It should be 0."

    except tarfile.ReadError:
        assert False, f"Failed to read {archive_path}. It must be a valid gzip-compressed tar archive."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
