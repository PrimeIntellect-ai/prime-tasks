#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import uuid
import pytest

EXECUTABLE = "/home/user/filter_manifest"
SOURCE = "/home/user/filter_manifest.cpp"


def run_filter(filepath):
    try:
        return subprocess.run(
            [EXECUTABLE, filepath],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Manifest filter timed out on {filepath}")


def test_incident_frame():
    filepath = "/home/user/incident_frame.txt"
    assert os.path.isfile(filepath), f"Missing file: {filepath}"
    with open(filepath, "r") as f:
        content = f.read().strip()
    assert content == "14", f"Expected frame '14', got '{content}'"


def test_manifest_filter_source_and_executable():
    assert os.path.isfile(SOURCE), f"Missing C++ source at {SOURCE}"
    assert os.path.isfile(EXECUTABLE), f"Missing executable at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable"


def test_manifest_filter_clean_corpus():
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Missing clean directory: {clean_dir}"

    clean_files = [
        os.path.join(clean_dir, f)
        for f in os.listdir(clean_dir)
        if os.path.isfile(os.path.join(clean_dir, f))
    ]
    assert len(clean_files) > 0, "No clean corpus files found to test."

    failed_files = []
    for filepath in clean_files:
        if run_filter(filepath) != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean modified "
            f"(expected exit code 0, got otherwise): {', '.join(failed_files)}"
        )


def test_manifest_filter_evil_corpus():
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Missing evil directory: {evil_dir}"

    evil_files = [
        os.path.join(evil_dir, f)
        for f in os.listdir(evil_dir)
        if os.path.isfile(os.path.join(evil_dir, f))
    ]
    assert len(evil_files) > 0, "No evil corpus files found to test."

    failed_files = []
    for filepath in evil_files:
        if run_filter(filepath) != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil bypassed "
            f"(expected exit code 1, got otherwise): {', '.join(failed_files)}"
        )


def test_manifest_filter_hidden_generated_manifests():
    rng = random.SystemRandom()
    cases = []

    # Generate valid addresses with verifier-time values that cannot be inferred
    # from public filenames or corpus paths.
    for _ in range(16):
        x = rng.randrange(0, 256)
        token = uuid.uuid4().hex
        content = f"BACKUP_JOB={token}\nTARGET_IP=10.0.0.{x}\nSTATUS=active\n"
        cases.append((content, 0))

    evil_ips = [
        f"192.168.{rng.randrange(0, 256)}.{rng.randrange(0, 256)}",
        f"10.0.1.{rng.randrange(0, 256)}",
        f"172.16.{rng.randrange(0, 256)}.{rng.randrange(0, 256)}",
        f"8.8.8.{rng.randrange(0, 256)}",
        f"10.0.0.{rng.randrange(256, 1000)}",
        "10.0.0.-1",
        "10.0.0.example",
        "10.0.0.12extra",
        "10.0.0.1.2",
        "10.0.0.",
    ]
    for ip in evil_ips:
        token = uuid.uuid4().hex
        content = f"BACKUP_JOB={token}\nTARGET_IP={ip}\nSTATUS=active\n"
        cases.append((content, 1))

    # Files without a correctly formed TARGET_IP line are malformed.
    cases.extend([
        (f"BACKUP_JOB={uuid.uuid4().hex}\nSTATUS=active\n", 1),
        (f"BACKUP_JOB={uuid.uuid4().hex}\nTARGET-IP=10.0.0.1\nSTATUS=active\n", 1),
        (f"BACKUP_JOB={uuid.uuid4().hex}\nTARGET_IP\nSTATUS=active\n", 1),
        ("", 1),
    ])

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="manifest-verification-") as root:
        materialized = []
        for content, expected in cases:
            # Names and locations intentionally contain no clean/evil indication.
            subdir = os.path.join(root, uuid.uuid4().hex)
            os.mkdir(subdir)
            path = os.path.join(subdir, uuid.uuid4().hex + ".txt")
            with open(path, "w") as f:
                f.write(content)
            materialized.append((path, expected))

        failures = []
        for path, expected in materialized:
            actual = run_filter(path)
            if actual != expected:
                failures.append((path, expected, actual))

        assert not failures, "Generated manifest failures: " + "; ".join(
            f"{os.path.basename(path)} expected {expected}, got {actual}"
            for path, expected, actual in failures
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
