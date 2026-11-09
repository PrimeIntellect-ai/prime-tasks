#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import gzip
import tarfile
import io
import fcntl
import shutil
import subprocess
import time
import pytest

SCRIPT_PATH = "/home/user/artifact_ingest.sh"
INCOMING_DIR = "/home/user/incoming"
REPO_DIR = "/home/user/repo"
LOCK_PATH = "/home/user/repo/repo.lock"


def get_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for block in iter(lambda: f.read(4096), b""):
            sha256.update(block)
    return sha256.hexdigest()


def test_script_exists_and_executable():
    script_path = "/home/user/artifact_ingest.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_script_uses_flock():
    script_path = "/home/user/artifact_ingest.sh"
    with open(script_path, 'r') as f:
        content = f.read()
    assert "flock" in content, "Script does not use 'flock' command for concurrency control."


def test_lock_file_exists():
    lock_path = "/home/user/repo/repo.lock"
    assert os.path.isfile(lock_path), f"Lock file {lock_path} does not exist."


def test_script_argument_handling():
    bad_invocations = [
        [SCRIPT_PATH],
        [SCRIPT_PATH, os.path.join(INCOMING_DIR, "file1.bin"), os.path.join(INCOMING_DIR, "file2.bin")],
        [SCRIPT_PATH, "file1.bin"],
    ]
    for command in bad_invocations:
        result = subprocess.run(
            command,
            cwd=INCOMING_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode != 0, f"Invalid invocation unexpectedly succeeded: {command}"


def test_script_obeys_repository_lock():
    probe_path = os.path.join(INCOMING_DIR, "verifier_probe.bin")
    with open(probe_path, "wb") as probe:
        probe.write(os.urandom(2 * 1024 * 1024 + 12345))

    probe_hash = get_sha256(probe_path)
    artifact_dir = os.path.join(REPO_DIR, probe_hash)
    shutil.rmtree(artifact_dir, ignore_errors=True)

    with open(LOCK_PATH, "a+") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        process = subprocess.Popen(
            [SCRIPT_PATH, probe_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        time.sleep(2)
        assert process.poll() is None, "Ingestion did not block while repo.lock was exclusively held."
        assert not os.path.exists(artifact_dir), "Script wrote the artifact before acquiring repo.lock."
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

        try:
            stdout, stderr = process.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            pytest.fail("Ingestion did not complete after repo.lock was released.")

    assert process.returncode == 0, (
        f"Script failed on a valid absolute input path. stdout={stdout!r}, stderr={stderr!r}"
    )
    assert os.path.isdir(artifact_dir), "Script did not create the probe artifact after the lock was released."


def test_execute_script_concurrently_on_all_inputs():
    input_paths = [os.path.join(INCOMING_DIR, f"file{i}.bin") for i in range(1, 6)]
    for filepath in input_paths:
        assert os.path.isfile(filepath), f"Expected input file {filepath} is missing."
        shutil.rmtree(os.path.join(REPO_DIR, get_sha256(filepath)), ignore_errors=True)

    processes = [
        subprocess.Popen([SCRIPT_PATH, filepath], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for filepath in input_paths
    ]

    for filepath, process in zip(input_paths, processes):
        try:
            stdout, stderr = process.communicate(timeout=120)
        except subprocess.TimeoutExpired:
            for running in processes:
                if running.poll() is None:
                    running.kill()
            for running in processes:
                running.communicate()
            pytest.fail(f"Concurrent ingestion timed out for {filepath}.")
        assert process.returncode == 0, (
            f"Concurrent ingestion failed for {filepath}. stdout={stdout!r}, stderr={stderr!r}"
        )


def test_artifacts_ingested_and_valid():
    incoming_dir = "/home/user/incoming"
    repo_dir = "/home/user/repo"

    # We expect file1.bin through file5.bin to be processed
    for i in range(1, 6):
        filename = f"file{i}.bin"
        filepath = os.path.join(incoming_dir, filename)
        assert os.path.isfile(filepath), f"Expected input file {filepath} is missing."

        file_hash = get_sha256(filepath)
        artifact_dir = os.path.join(repo_dir, file_hash)
        assert os.path.isdir(artifact_dir), f"Artifact directory {artifact_dir} missing for {filename}."

        manifest_path = os.path.join(artifact_dir, "manifest.txt")
        assert os.path.isfile(manifest_path), f"Manifest missing in {artifact_dir}."

        with open(manifest_path, 'r') as f:
            manifest_lines = [line.strip() for line in f.readlines() if line.strip()]

        assert len(manifest_lines) >= 4, f"Manifest in {artifact_dir} is incomplete."
        assert manifest_lines[0] == f"Original: {filename}", f"Manifest Original line incorrect in {manifest_path}."
        assert manifest_lines[1] == f"Original-SHA256: {file_hash}", f"Manifest Original-SHA256 line incorrect in {manifest_path}."
        assert manifest_lines[2] == "Chunks:", f"Manifest Chunks header missing in {manifest_path}."

        chunks_in_dir = sorted([c for c in os.listdir(artifact_dir) if c.startswith("chunk_")])
        assert len(chunks_in_dir) > 0, f"No chunks found in {artifact_dir}."

        chunk_lines = manifest_lines[3:]
        assert len(chunk_lines) == len(chunks_in_dir), f"Manifest chunk count mismatch in {manifest_path}."

        chunk_data = b""
        for chunk_line, chunk_file in zip(chunk_lines, chunks_in_dir):
            chunk_path = os.path.join(artifact_dir, chunk_file)
            chunk_hash = get_sha256(chunk_path)
            assert chunk_line == f"{chunk_file} {chunk_hash}", f"Manifest chunk entry incorrect for {chunk_file}."

            with open(chunk_path, 'rb') as cf:
                chunk_data += cf.read()

        # Reassemble and verify integrity
        try:
            decompressed = gzip.decompress(chunk_data)
        except Exception as e:
            pytest.fail(f"Failed to decompress chunks for {filename}: {e}")

        try:
            with tarfile.open(fileobj=io.BytesIO(decompressed), mode="r") as tar:
                members = tar.getmembers()
                assert len(members) == 1, f"Tarball should contain exactly 1 file, found {len(members)}."
                assert members[0].name == filename, f"Tarball contains {members[0].name}, expected {filename}."

                extracted_f = tar.extractfile(members[0])
                extracted_data = extracted_f.read()

                extracted_hash = hashlib.sha256(extracted_data).hexdigest()
                assert extracted_hash == file_hash, f"Reassembled file hash does not match original for {filename}."
        except Exception as e:
            pytest.fail(f"Failed to read tarball for {filename}: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
