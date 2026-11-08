#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import random
import shutil
import subprocess
import tarfile
import tempfile
import uuid

import pytest

LIMIT = 10 * 1024 * 1024
SCRIPT_PATH = "/home/user/cleanup.py"


class ZeroReader:
    def __init__(self, size):
        self.remaining = size

    def read(self, count=-1):
        if self.remaining == 0:
            return b""
        if count < 0 or count > self.remaining:
            count = self.remaining
        self.remaining -= count
        return b"\0" * count


def make_archive(path, members):
    with tarfile.open(path, "w:gz") as archive:
        for member_name, size in members:
            info = tarfile.TarInfo(member_name)
            info.size = size
            info.mode = 0o600
            archive.addfile(info, ZeroReader(size))


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def test_cleanup_script_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"

    clean_corpus_path = "/app/corpora/clean"
    evil_corpus_path = "/app/corpora/evil"

    assert os.path.isdir(clean_corpus_path), "Clean corpus missing."
    assert os.path.isdir(evil_corpus_path), "Evil corpus missing."

    clean_files = os.listdir(clean_corpus_path)
    evil_files = os.listdir(evil_corpus_path)

    with tempfile.TemporaryDirectory() as staging_dir:
        for f in clean_files:
            shutil.copy(os.path.join(clean_corpus_path, f), staging_dir)
        for f in evil_files:
            shutil.copy(os.path.join(evil_corpus_path, f), staging_dir)

        result = subprocess.run(
            ["python3", SCRIPT_PATH, staging_dir],
            capture_output=True,
            text=True
        )

        assert result.returncode == 0, f"Script failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

        staging_files = os.listdir(staging_dir)

        evil_bypassed = []
        for f in evil_files:
            if f in staging_files or f"approved_{f}" in staging_files:
                evil_bypassed.append(f)

        clean_modified_or_missing = []
        for f in clean_files:
            expected_name = f"approved_{f}"
            if expected_name not in staging_files:
                clean_modified_or_missing.append(f)

        extracted_items = []
        for item in staging_files:
            item_path = os.path.join(staging_dir, item)
            if os.path.isdir(item_path):
                extracted_items.append(item)
            elif item not in evil_files and not item.startswith("approved_"):
                extracted_items.append(item)

        error_messages = []
        if evil_bypassed:
            error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
        if clean_modified_or_missing:
            error_messages.append(f"{len(clean_modified_or_missing)} of {len(clean_files)} clean modified or missing: {', '.join(clean_modified_or_missing)}")
        if extracted_items:
            error_messages.append(f"Archives were extracted to disk or unexpected files created: {', '.join(extracted_items)}")

        if error_messages:
            pytest.fail(" | ".join(error_messages))


def test_cleanup_on_generated_archives():
    assert os.path.isfile(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"

    token = uuid.uuid4().hex
    cases = [
        (True, [(f"{uuid.uuid4().hex}.txt", 12345)]),
        (True, [(f"{uuid.uuid4().hex}.bin", LIMIT // 2), (f"nested/{uuid.uuid4().hex}.dat", LIMIT // 2)]),
        (True, [(f"{uuid.uuid4().hex}.exe.txt", 0)]),
        (False, [(f"{uuid.uuid4().hex}.bin", LIMIT + 1)]),
        (False, [(f"nested/{uuid.uuid4().hex}.exe", 1)]),
        (False, [(f"{uuid.uuid4().hex}.part", LIMIT // 2 + 1), (f"{uuid.uuid4().hex}.part", LIMIT // 2)]),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory() as staging_dir:
        expected_files = set()
        expected_digests = {}

        for index, (compliant, members) in enumerate(cases):
            archive_name = f"{token}_{index}_{uuid.uuid4().hex}.tar.gz"
            archive_path = os.path.join(staging_dir, archive_name)
            make_archive(archive_path, members)
            if compliant:
                approved_name = f"approved_{archive_name}"
                expected_files.add(approved_name)
                expected_digests[approved_name] = digest(archive_path)

        result = subprocess.run(
            ["python3", SCRIPT_PATH, staging_dir],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Script failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

        actual_files = set(os.listdir(staging_dir))
        assert actual_files == expected_files, (
            f"Incorrect generated-corpus result. Expected {sorted(expected_files)}, got {sorted(actual_files)}"
        )

        for approved_name, original_digest in expected_digests.items():
            approved_path = os.path.join(staging_dir, approved_name)
            assert os.path.isfile(approved_path), f"Expected regular archive missing: {approved_name}"
            assert digest(approved_path) == original_digest, f"Compliant archive contents were changed: {approved_name}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
