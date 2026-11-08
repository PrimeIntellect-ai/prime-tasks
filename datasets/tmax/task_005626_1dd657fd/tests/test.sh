#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import shutil
import subprocess
import tarfile

import pytest

EXPECTED_FILES = {"app_20220315.log", "app_20220620.log", "app_20221105.log"}


@pytest.fixture(scope="session", autouse=True)
def execute_restore_script_from_chunks():
    """Require the submitted script to recreate all outputs without source logs."""
    script_path = "/home/user/restore.sh"
    assert os.path.isfile(script_path), f"Restore script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Restore script {script_path} is not executable."

    restored_dir = "/home/user/restored_logs"
    checksum_file = "/home/user/restored_checksums.txt"
    original_logs = "/home/user/logs"
    hidden_logs = "/home/user/logs.verifier-hidden"

    if os.path.lexists(hidden_logs):
        if os.path.isdir(hidden_logs) and not os.path.islink(hidden_logs):
            shutil.rmtree(hidden_logs)
        else:
            os.unlink(hidden_logs)

    if os.path.lexists(restored_dir):
        if os.path.isdir(restored_dir) and not os.path.islink(restored_dir):
            shutil.rmtree(restored_dir)
        else:
            os.unlink(restored_dir)
    os.makedirs(restored_dir)

    if os.path.lexists(checksum_file):
        os.unlink(checksum_file)

    os.rename(original_logs, hidden_logs)
    try:
        result = subprocess.run(
            [script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=60,
        )
    finally:
        if os.path.lexists(original_logs):
            if os.path.isdir(original_logs) and not os.path.islink(original_logs):
                shutil.rmtree(original_logs)
            else:
                os.unlink(original_logs)
        os.rename(hidden_logs, original_logs)

    assert result.returncode == 0, (
        f"Restore script exited with status {result.returncode}. Output:\n{result.stdout}"
    )


def test_restore_script_exists_and_executable():
    script_path = "/home/user/restore.sh"
    assert os.path.isfile(script_path), f"Restore script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Restore script {script_path} is not executable."


def test_restored_logs_contents():
    restored_dir = "/home/user/restored_logs"
    assert os.path.isdir(restored_dir), f"Directory {restored_dir} does not exist."

    actual_files = set(os.listdir(restored_dir))
    assert actual_files == EXPECTED_FILES, (
        f"Restored logs directory contains {actual_files}, expected {EXPECTED_FILES}."
    )


def test_archived_chunks_sizes():
    chunks_dir = "/home/user/archived_chunks"
    assert os.path.isdir(chunks_dir), f"Directory {chunks_dir} does not exist."

    chunks = sorted([f for f in os.listdir(chunks_dir) if f.startswith("archive.part.")])
    assert len(chunks) > 0, "No archive chunks found starting with 'archive.part.'."

    for i, chunk in enumerate(chunks):
        chunk_path = os.path.join(chunks_dir, chunk)
        size = os.path.getsize(chunk_path)
        if i < len(chunks) - 1:
            assert size == 2097152, (
                f"Chunk {chunk} has size {size}, expected exactly 2097152 bytes."
            )
        else:
            assert size <= 2097152, (
                f"Last chunk {chunk} has size {size}, expected <= 2097152 bytes."
            )


def test_chunks_form_correct_tar_gz_archive():
    chunks_dir = "/home/user/archived_chunks"
    chunks = sorted(
        f for f in os.listdir(chunks_dir) if f.startswith("archive.part.")
    )
    archive_data = b"".join(
        open(os.path.join(chunks_dir, chunk), "rb").read() for chunk in chunks
    )

    try:
        with tarfile.open(fileobj=io.BytesIO(archive_data), mode="r:gz") as archive:
            members = archive.getmembers()
            assert all(member.isfile() for member in members), (
                "Archive must contain only regular log files."
            )
            assert {member.name for member in members} == EXPECTED_FILES, (
                "Archive does not contain exactly the required 2022 logs at its root."
            )
            assert len(members) == len(EXPECTED_FILES), (
                "Archive contains duplicate or unexpected entries."
            )

            for member in members:
                archived_file = archive.extractfile(member)
                assert archived_file is not None
                archived_hash = hashlib.sha256(archived_file.read()).hexdigest()
                source_path = os.path.join("/home/user/logs", member.name)
                with open(source_path, "rb") as source_file:
                    source_hash = hashlib.sha256(source_file.read()).hexdigest()
                assert archived_hash == source_hash, (
                    f"Archived content for {member.name} does not match the source log."
                )
    except (tarfile.TarError, OSError, EOFError) as exc:
        pytest.fail(f"Concatenated chunks are not a valid tar.gz archive: {exc}")


def test_restored_checksums():
    checksum_file = "/home/user/restored_checksums.txt"
    assert os.path.isfile(checksum_file), f"Checksum file {checksum_file} does not exist."

    original_logs_dir = "/home/user/logs"
    expected_files = sorted(EXPECTED_FILES)

    expected_lines = []
    for filename in expected_files:
        filepath = os.path.join(original_logs_dir, filename)
        assert os.path.isfile(filepath), f"Original log file {filepath} missing."

        sha256_hash = hashlib.sha256()
        with open(filepath, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)

        expected_lines.append(f"{sha256_hash.hexdigest()}  {filename}")

    with open(checksum_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        "Checksum file contents do not match the expected SHA256 hashes and filenames."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
