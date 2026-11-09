#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import fcntl
import hashlib
import io
import json
import os
import subprocess
import tarfile
import time
import uuid
from pathlib import Path

import pytest

CLEAN_CORPUS = Path("/app/corpus/clean/")
EVIL_CORPUS = Path("/app/corpus/evil/")
SCRIPT_PATH = Path("/home/user/validate_doc_archive.sh")
REFERENCE_FRAME = Path("/home/user/reference_frame.jpg")
SCREENCAST = Path("/app/screencast.mp4")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def run_validator(archive, seconds=5):
    return subprocess.run(
        ["timeout", str(seconds), str(SCRIPT_PATH), str(archive)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def write_tar(path, members):
    with tarfile.open(path, "w:gz") as tf:
        for name, data in members.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(data))


def archive_members(metadata, frame, manifest):
    return {
        "manifest.json": json.dumps(manifest).encode(),
        "metadata.csv": metadata,
        "frame.jpg": frame,
    }


def random_archive(tmp_path):
    return tmp_path / (uuid.uuid4().hex + ".tar.gz")


def test_reference_frame_extracted(tmp_path):
    assert REFERENCE_FRAME.exists(), f"Missing extracted reference frame at {REFERENCE_FRAME}"
    assert REFERENCE_FRAME.is_file(), f"{REFERENCE_FRAME} is not a file"
    assert REFERENCE_FRAME.stat().st_size > 0, f"{REFERENCE_FRAME} is empty"

    expected = tmp_path / "expected-reference.jpg"
    subprocess.run(
        [
            "ffmpeg", "-loglevel", "error", "-y", "-ss", "00:00:10",
            "-i", str(SCREENCAST), "-frames:v", "1", str(expected),
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert sha256(REFERENCE_FRAME.read_bytes()) == sha256(expected.read_bytes()), \
        "reference_frame.jpg is not the frame extracted at 00:00:10"


def test_script_exists_and_executable():
    assert SCRIPT_PATH.exists(), f"Missing script at {SCRIPT_PATH}"
    assert SCRIPT_PATH.is_file(), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_clean_corpus():
    clean_files = list(CLEAN_CORPUS.glob("*.tar.gz"))
    assert len(clean_files) > 0, "No clean archives found to test."

    failed_clean = []
    for archive in clean_files:
        result = run_validator(archive)
        if result.returncode != 0:
            failed_clean.append(archive.name)

    assert not failed_clean, f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}"


def test_evil_corpus():
    evil_files = list(EVIL_CORPUS.glob("*.tar.gz"))
    assert len(evil_files) > 0, "No evil archives found to test."

    failed_evil = []
    for archive in evil_files:
        lock_file = archive.with_name(archive.name + ".lock")
        lock_fd = None

        if archive.name == "evil_1.tar.gz":
            lock_fd = open(lock_file, "w")
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                pass

        try:
            result = run_validator(archive)
            if result.returncode == 0:
                failed_evil.append(archive.name)
        finally:
            if lock_fd:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
                lock_fd.close()
                if lock_file.exists():
                    try:
                        lock_file.unlink()
                    except OSError:
                        pass

    assert not failed_evil, f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}"


def test_randomized_archives_and_locking(tmp_path):
    reference = REFERENCE_FRAME.read_bytes()
    true_metadata = b"type,value\nreference,true\n"
    false_metadata = b"type,value\nreference,false\n"

    valid_manifest = {
        "metadata.csv": sha256(true_metadata),
        "frame.jpg": sha256(reference),
    }

    valid = random_archive(tmp_path)
    write_tar(valid, archive_members(true_metadata, reference, valid_manifest))
    assert run_validator(valid).returncode == 0, "randomly named valid archive was rejected"

    alternate_frame = b"an alternate non-reference frame"
    false_manifest = {
        "metadata.csv": sha256(false_metadata),
        "frame.jpg": sha256(alternate_frame),
    }
    valid_nonreference = random_archive(tmp_path)
    write_tar(valid_nonreference, archive_members(false_metadata, alternate_frame, false_manifest))
    assert run_validator(valid_nonreference).returncode == 0, \
        "valid archive with reference=false was rejected"

    invalid_archives = []

    malformed = random_archive(tmp_path)
    write_tar(malformed, {
        "manifest.json": b"{not valid json",
        "metadata.csv": true_metadata,
        "frame.jpg": reference,
    })
    invalid_archives.append((malformed, "malformed manifest"))

    mismatch = random_archive(tmp_path)
    bad_manifest = dict(valid_manifest)
    bad_manifest["metadata.csv"] = "0" * 64
    write_tar(mismatch, archive_members(true_metadata, reference, bad_manifest))
    invalid_archives.append((mismatch, "checksum mismatch"))

    missing_listed = random_archive(tmp_path)
    listed_manifest = dict(valid_manifest)
    listed_manifest["extra.bin"] = sha256(b"expected contents")
    write_tar(missing_listed, archive_members(true_metadata, reference, listed_manifest))
    invalid_archives.append((missing_listed, "missing manifest-listed file"))

    traversal = random_archive(tmp_path)
    traversal_manifest = dict(valid_manifest)
    traversal_manifest["../escape"] = sha256(b"escape")
    write_tar(traversal, archive_members(true_metadata, reference, traversal_manifest))
    invalid_archives.append((traversal, "manifest traversal path"))

    absolute = random_archive(tmp_path)
    absolute_manifest = dict(valid_manifest)
    absolute_manifest["/tmp/escape"] = sha256(b"escape")
    write_tar(absolute, archive_members(true_metadata, reference, absolute_manifest))
    invalid_archives.append((absolute, "absolute manifest path"))

    wrong_frame = b"not the reference frame"
    wrong_reference = random_archive(tmp_path)
    wrong_manifest = {
        "metadata.csv": sha256(true_metadata),
        "frame.jpg": sha256(wrong_frame),
    }
    write_tar(wrong_reference, archive_members(true_metadata, wrong_frame, wrong_manifest))
    invalid_archives.append((wrong_reference, "wrong required reference frame"))

    missing_required = random_archive(tmp_path)
    write_tar(missing_required, {
        "manifest.json": json.dumps({"metadata.csv": sha256(true_metadata)}).encode(),
        "metadata.csv": true_metadata,
    })
    invalid_archives.append((missing_required, "missing required frame.jpg"))

    corrupt = random_archive(tmp_path)
    corrupt.write_bytes(b"not a gzip-compressed tar archive")
    invalid_archives.append((corrupt, "invalid tar.gz"))

    for archive, description in invalid_archives:
        assert run_validator(archive).returncode != 0, \
            f"randomly named archive with {description} was accepted"

    lock_path = Path(str(valid) + ".lock")
    with open(lock_path, "w") as lock_fd:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        started = time.monotonic()
        result = run_validator(valid)
        elapsed = time.monotonic() - started
        assert result.returncode != 0, "validator accepted an archive whose lock was held"
        assert elapsed < 4.5, "validator did not reject a held lock within the required time"
        fcntl.flock(lock_fd, fcntl.LOCK_UN)

    try:
        lock_path.unlink()
    except FileNotFoundError:
        pass

    assert run_validator(valid).returncode == 0, \
        "validator did not accept the valid archive after its lock was released"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
