#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tarfile
import tempfile
import pytest

SCRIPT_PATH = "/home/user/sanitizer.sh"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable."


def test_adversarial_corpus():
    clean_failures = []
    evil_failures = []

    # Test clean corpus
    if os.path.isdir(CLEAN_CORPUS_DIR):
        for filename in os.listdir(CLEAN_CORPUS_DIR):
            if filename.endswith(".tar"):
                filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
                result = subprocess.run(["bash", SCRIPT_PATH, filepath], capture_output=True)
                if result.returncode != 0:
                    clean_failures.append(filename)

    # Test evil corpus
    if os.path.isdir(EVIL_CORPUS_DIR):
        for filename in os.listdir(EVIL_CORPUS_DIR):
            if filename.endswith(".tar"):
                filepath = os.path.join(EVIL_CORPUS_DIR, filename)
                result = subprocess.run(["bash", SCRIPT_PATH, filepath], capture_output=True)
                if result.returncode != 1:
                    evil_failures.append(filename)

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} clean modified/rejected: {', '.join(clean_failures)}")

    assert not error_messages, " | ".join(error_messages)


def test_randomized_archives_require_content_inspection():
    rng = random.SystemRandom()

    def token():
        return secrets.token_hex(8)

    def forbidden(name):
        return (
            name.startswith("/")
            or ".." in name.split("/")
            or name.endswith(".wal")
        )

    cases = [
        [f"{token()}/{token()}.json", f"{token()}/{token()}.txt"],
        [f"{token()}/walrus.txt", f"{token()}/{token()}.wal.bak"],
        [f"{token()}/dot..name", f"{token()}/{token()}.conf"],
        [f"../{token()}.txt"],
        [f"{token()}/../{token()}.conf"],
        [f"{token()}/x/../../{token()}.sh"],
        [f"/{token()}/{token()}.txt"],
        [f"{token()}/{token()}.wal"],
        [f"{token()}/.."],
        [f"{token()}/{token()}.txt", f"{token()}/{token()}.wal"],
    ]
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="archive_checks_") as directory:
        runs = []
        for members in cases:
            archive = os.path.join(directory, token() + ".tar")
            with tarfile.open(archive, "w") as tf:
                for member in members:
                    info = tarfile.TarInfo(member)
                    info.size = 0
                    tf.addfile(info)
            expected = 1 if any(forbidden(member) for member in members) else 0
            runs.append((archive, expected))

        rng.shuffle(runs)
        failures = []
        for archive, expected in runs:
            result = subprocess.run(["bash", SCRIPT_PATH, archive], capture_output=True)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(archive)} returned {result.returncode}, expected {expected}"
                )

        assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
