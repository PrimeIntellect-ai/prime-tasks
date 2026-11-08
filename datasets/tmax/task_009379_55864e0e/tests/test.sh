#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import os
import shutil
import subprocess
import tarfile
import tempfile

import pytest

SOURCE = "/home/user/archiver.c"
BINARY = "/home/user/archiver"
GENERATOR = "/home/user/generator.sh"
BACKUP = "/home/user/final_backup.tar.gz"
SOURCE_BINARY = "/tmp/archiver_from_source"
SOURCE_BACKUP = "/tmp/source_final_backup.tar.gz"


def known_generator_output():
    lines = []
    for i in range(1, 126):
        timestamp = datetime.datetime.fromtimestamp(
            1600000000 + i, datetime.timezone.utc
        ).strftime("%Y-%m-%dT%H:%M:%SZ")
        lines.append(f"Log entry {i}: {timestamp} - DATA BLOCK {i}\n")
    return "".join(lines).encode()


def run_archiver(binary):
    shutil.rmtree("/home/user/archive_dir", ignore_errors=True)
    try:
        os.remove(BACKUP)
    except FileNotFoundError:
        pass

    command = f"{GENERATOR} | {binary}"
    result = subprocess.run(
        ["bash", "-o", "pipefail", "-c", command],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Archiver pipeline failed for {binary} with status {result.returncode}: "
        + result.stderr.decode(errors="replace")
    )
    assert os.path.exists(BACKUP), f"{binary} did not create {BACKUP}"


@pytest.fixture(scope="session", autouse=True)
def build_and_execute_artifacts():
    assert os.path.isfile(SOURCE), f"Required C source {SOURCE} does not exist."
    assert os.path.isfile(BINARY), f"Required executable {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."

    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", SOURCE_BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "archiver.c failed to compile: "
        + compile_result.stderr.decode(errors="replace")
    )

    actual_generator_output = subprocess.check_output([GENERATOR], timeout=15)
    assert actual_generator_output == known_generator_output(), (
        "generator.sh no longer produces the pre-existing 125-line mock stream."
    )

    # Exercise a fresh build of the submitted source as well as the required
    # installed executable. Preserve the first result for content checks.
    run_archiver(SOURCE_BINARY)
    shutil.copyfile(BACKUP, SOURCE_BACKUP)
    run_archiver(BINARY)


def inspect_backup(backup_path):
    assert os.path.exists(backup_path), "Backup archive missing."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(backup_path, "r:gz") as tar:
            tar.extractall(path=tmpdir)

        # Find the files (they might be in archive_dir or at the archive root).
        manifest_path = None
        chunk1_path = None
        chunk2_path = None
        chunk3_path = None

        for root, dirs, files in os.walk(tmpdir):
            if "manifest.txt" in files:
                manifest_path = os.path.join(root, "manifest.txt")
            if "chunk_1.txt" in files:
                chunk1_path = os.path.join(root, "chunk_1.txt")
            if "chunk_2.txt" in files:
                chunk2_path = os.path.join(root, "chunk_2.txt")
            if "chunk_3.txt" in files:
                chunk3_path = os.path.join(root, "chunk_3.txt")

        assert manifest_path is not None, "manifest.txt not found in the archive."
        assert chunk1_path is not None, "chunk_1.txt not found in the archive."
        assert chunk2_path is not None, "chunk_2.txt not found in the archive."
        assert chunk3_path is not None, "chunk_3.txt not found in the archive."

        with open(chunk1_path, "r") as f:
            chunk1_lines = f.readlines()
        assert len(chunk1_lines) == 50, f"Expected chunk_1.txt to have 50 lines, got {len(chunk1_lines)}"

        with open(chunk2_path, "r") as f:
            chunk2_lines = f.readlines()
        assert len(chunk2_lines) == 50, f"Expected chunk_2.txt to have 50 lines, got {len(chunk2_lines)}"

        with open(chunk3_path, "r") as f:
            chunk3_lines = f.readlines()
        assert len(chunk3_lines) == 25, f"Expected chunk_3.txt to have 25 lines, got {len(chunk3_lines)}"

        chunk_paths = [chunk1_path, chunk2_path, chunk3_path]
        chunk_data = []
        for path in chunk_paths:
            with open(path, "rb") as f:
                chunk_data.append(f.read())

        expected_lines = known_generator_output().splitlines(keepends=True)
        assert chunk_data[0] == b"".join(expected_lines[:50]), "chunk_1.txt does not contain generator lines 1-50."
        assert chunk_data[1] == b"".join(expected_lines[50:100]), "chunk_2.txt does not contain generator lines 51-100."
        assert chunk_data[2] == b"".join(expected_lines[100:]), "chunk_3.txt does not contain generator lines 101-125."

        def get_md5(filepath):
            hash_md5 = hashlib.md5()
            with open(filepath, "rb") as f:
                for chunk in iter(lambda: f.read(4096), b""):
                    hash_md5.update(chunk)
            return hash_md5.hexdigest()

        expected_md5 = {
            "chunk_1.txt": get_md5(chunk1_path),
            "chunk_2.txt": get_md5(chunk2_path),
            "chunk_3.txt": get_md5(chunk3_path),
        }

        with open(manifest_path, "r") as f:
            manifest_text = f.read()
        manifest_lines = manifest_text.strip().split("\n")

        manifest_dict = {}
        for line in manifest_lines:
            if not line.strip():
                continue
            parts = line.strip().split()
            assert len(parts) >= 2, f"Invalid manifest line format: {line}"
            md5_val = parts[0]
            filename = parts[-1]
            manifest_dict[os.path.basename(filename)] = md5_val

        for chunk_name, expected_hash in expected_md5.items():
            assert chunk_name in manifest_dict, f"{chunk_name} missing from manifest.txt"
            assert manifest_dict[chunk_name] == expected_hash, f"MD5 mismatch for {chunk_name}: expected {expected_hash}, got {manifest_dict[chunk_name]}"

        exact_manifest = "".join(
            f"{expected_md5[name]}  {name}\n"
            for name in ("chunk_1.txt", "chunk_2.txt", "chunk_3.txt")
        )
        assert manifest_text == exact_manifest, "manifest.txt does not use the required exact format and ordering."


def test_final_backup_exists():
    assert os.path.exists(BACKUP), "The final backup archive /home/user/final_backup.tar.gz does not exist."


def test_final_backup_contents():
    inspect_backup(BACKUP)


def test_freshly_compiled_source_contents():
    inspect_backup(SOURCE_BACKUP)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
