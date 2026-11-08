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


def sha256_stream(stream):
    digest = hashlib.sha256()
    while True:
        chunk = stream.read(1024 * 1024)
        if not chunk:
            break
        digest.update(chunk)
    return digest.hexdigest()


def expected_zero_hash():
    digest = hashlib.sha256()
    chunk = b"\0" * (1024 * 1024)
    for _ in range(10):
        digest.update(chunk)
    return digest.hexdigest()


def test_corruption_log():
    log_path = "/home/user/corruption.log"
    assert os.path.isfile(log_path), f"Corruption log is missing at {log_path}"
    with open(log_path, "r") as f:
        content = f.read()
    assert "719" in content, "Corruption log does not mention the corrupted artifact ID 719"


def test_curated_release_archive():
    archive_path = "/home/user/curated_release.tar.xz"
    assert os.path.isfile(archive_path), f"Final archive is missing at {archive_path}"

    file_size = os.path.getsize(archive_path)
    threshold = 5000
    assert file_size <= threshold, (
        f"Archive size {file_size} bytes exceeds the maximum allowed size of "
        f"{threshold} bytes. Use stronger compression."
    )

    expected_files = {
        "release_105_stable.bin",
        "release_302_stable.bin",
        "release_884_stable.bin",
    }
    expected_hash = expected_zero_hash()

    try:
        with tarfile.open(archive_path, "r:xz") as tar:
            members = tar.getmembers()
            file_members = [member for member in members if member.isfile()]
            file_names = [os.path.basename(member.name) for member in file_members]

            actual_files = set(file_names)
            assert actual_files == expected_files, (
                f"Archive contents do not match expected files. "
                f"Expected {expected_files}, got {actual_files}"
            )
            assert len(file_members) == len(expected_files), (
                "Archive contains duplicate or unexpected regular-file entries"
            )

            for member in file_members:
                name = os.path.basename(member.name)
                assert member.size == 10 * 1024 * 1024, (
                    f"{name} has size {member.size}, expected 10485760 bytes"
                )
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read {name} from archive"
                assert sha256_stream(extracted) == expected_hash, (
                    f"{name} does not preserve the expected binary contents"
                )
    except (AssertionError, pytest.fail.Exception):
        raise
    except Exception as e:
        pytest.fail(f"Failed to open the archive {archive_path} as a tar.xz file: {e}")


def fixture_bytes(artifact_id):
    return b"".join(
        hashlib.sha256(f"{artifact_id}:{index}".encode()).digest()
        for index in range(8192)
    )


def write_fixture_archive(path, content):
    info = tarfile.TarInfo("raw_binary.bin")
    info.size = len(content)
    info.mode = 0o644
    with tarfile.open(path, "w:gz") as archive:
        archive.addfile(info, io.BytesIO(content))


def test_compiled_curator_processes_archives():
    program = "/home/user/curate"
    assert os.path.isfile(program), f"Compiled curator is missing at {program}"
    assert os.access(program, os.X_OK), f"Curator is not executable: {program}"
    with open(program, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", (
            "/home/user/curate must be a compiled executable"
        )

    expected = {}
    for artifact_id in (105, 302, 884):
        content = fixture_bytes(artifact_id)
        expected[artifact_id] = hashlib.sha256(content).hexdigest()
        write_fixture_archive(
            f"/app/repo/artifact_{artifact_id}.tar.gz", content
        )

    corrupt_path = "/app/repo/artifact_719.tar.gz"
    write_fixture_archive(corrupt_path, fixture_bytes(719))
    with open(corrupt_path, "r+b") as archive:
        archive.truncate(max(1, os.path.getsize(corrupt_path) // 2))

    staging = "/home/user/staging"
    if os.path.lexists(staging):
        if os.path.isdir(staging) and not os.path.islink(staging):
            shutil.rmtree(staging)
        else:
            os.unlink(staging)
    os.makedirs(staging)

    log_path = "/home/user/corruption.log"
    if os.path.lexists(log_path):
        if os.path.isdir(log_path) and not os.path.islink(log_path):
            shutil.rmtree(log_path)
        else:
            os.unlink(log_path)

    try:
        result = subprocess.run(
            [program, "105", "302", "719", "884"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            text=True,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The curator did not finish within 30 seconds")

    expected_names = {
        f"release_{artifact_id}_stable.bin" for artifact_id in expected
    }
    actual_names = set(os.listdir(staging))
    assert actual_names == expected_names, (
        f"Curator produced incorrect staging contents. "
        f"Expected {expected_names}, got {actual_names}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    for artifact_id, expected_hash in expected.items():
        output = os.path.join(staging, f"release_{artifact_id}_stable.bin")
        assert os.path.isfile(output), f"Missing regular output file {output}"
        with open(output, "rb") as stream:
            assert sha256_stream(stream) == expected_hash, (
                f"Curator did not faithfully extract artifact {artifact_id}"
            )

    assert os.path.isfile(log_path), "Curator did not create corruption.log"
    with open(log_path, "r") as log:
        assert "719" in log.read(), "Curator did not log corrupted artifact 719"
    assert not os.path.exists(os.path.join(staging, "release_719_stable.bin")), (
        "Curator extracted corrupted artifact 719 instead of skipping it"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
