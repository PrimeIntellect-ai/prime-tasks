#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import subprocess
import tempfile
import pytest


def recover_deleted_files_from_image():
    """Recover the bytes of all deleted inodes directly from the ext4 image."""
    image_path = "/app/log_volume.img"
    assert os.path.isfile(image_path), f"Missing filesystem image: {image_path}"

    proc = subprocess.run(
        ["debugfs", "-R", "lsdel", image_path],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"Unable to inspect deleted inodes: {proc.stderr}"

    inode_numbers = []
    for line in proc.stdout.splitlines():
        fields = line.split()
        if (
            len(fields) >= 4
            and fields[0].isdigit()
            and fields[1].isdigit()
            and re.fullmatch(r"[0-7]{6}", fields[2])
            and fields[3].isdigit()
        ):
            inode_numbers.append(int(fields[0]))

    assert inode_numbers, "The filesystem image contains no recoverable deleted inodes."

    recovered = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for inode in inode_numbers:
            output_path = os.path.join(tmpdir, f"inode-{inode}")
            dump = subprocess.run(
                ["debugfs", "-R", f"dump <{inode}> {output_path}", image_path],
                capture_output=True,
                text=True,
            )
            if dump.returncode == 0 and os.path.isfile(output_path):
                with open(output_path, "rb") as f:
                    recovered.append(f.read())
    assert recovered, "Unable to recover any deleted file from the filesystem image."
    return recovered


def test_recovered_log():
    """Verify the recovered log is the actual deleted file from the ext4 image."""
    log_path = "/home/user/recovered_system.log"
    assert os.path.isfile(log_path), f"Missing recovered log file: {log_path}"
    with open(log_path, "rb") as f:
        recovered_log = f.read()

    content = recovered_log.decode("utf-8", errors="replace")
    assert "2024-05-12 09:15:33" in content, "Recovered log does not contain the entry for the crash timestamp (2024-05-12 09:15:33)."

    deleted_files = recover_deleted_files_from_image()
    assert recovered_log in deleted_files, "Recovered log is not byte-for-byte equal to any deleted file recoverable from /app/log_volume.img."


def test_crash_cause():
    """Verify the crash cause file contains the exact malicious payload."""
    cause_path = "/home/user/crash_cause.txt"
    assert os.path.isfile(cause_path), f"Missing crash cause file: {cause_path}"
    with open(cause_path, "r", errors="replace") as f:
        content = f.read().strip()
    expected = '/var/drop/payload; rm -rf /; echo "hacked"'
    assert content == expected, f"Crash cause file content mismatch. Expected: '{expected}', Got: '{content}'"


def test_sanitizer_exists_and_executable():
    """Verify the sanitizer binary is compiled and executable."""
    sanitizer_path = "/home/user/sanitizer"
    assert os.path.isfile(sanitizer_path), f"Missing compiled sanitizer executable: {sanitizer_path}"
    assert os.access(sanitizer_path, os.X_OK), f"Sanitizer is not executable: {sanitizer_path}"


def run_sanitizer(payload):
    return subprocess.run(
        ["/home/user/sanitizer"],
        input=payload,
        capture_output=True,
    )


def test_sanitizer_adversarial_corpus():
    """Evaluate the sanitizer against the supplied corpus without storage newlines."""
    evil_corpus = glob.glob("/app/corpus/evil/*")
    clean_corpus = glob.glob("/app/corpus/clean/*")

    assert len(evil_corpus) > 0, "Evil corpus is empty or missing in the environment."
    assert len(clean_corpus) > 0, "Clean corpus is empty or missing in the environment."

    evil_bypassed = []
    for evil_file in evil_corpus:
        with open(evil_file, "rb") as f:
            payload = f.read()
        proc = run_sanitizer(payload)
        if proc.returncode == 0:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_corpus:
        with open(clean_file, "rb") as f:
            payload = f.read()
        # echo added this newline as a corpus-file delimiter; it is not part of
        # the clean filename that must be supplied to the sanitizer.
        if payload.endswith(b"\n"):
            payload = payload[:-1]
        proc = run_sanitizer(payload)
        if proc.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_corpus)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_corpus)} clean modified: {', '.join(clean_modified)}")
    if error_msgs:
        pytest.fail("Sanitizer failed adversarial checks. " + "; ".join(error_msgs))


def test_sanitizer_rejects_derived_malicious_inputs():
    """Exercise each prohibited character without relying on corpus labels."""
    malicious = [b"file with space.txt"]
    malicious.extend(b"safe" + bytes([ch]) + b"name" for ch in b";&|*$<>()`")
    malicious.extend(b"safe" + bytes([ch]) + b"name" for ch in range(0, 32))
    malicious.append(b"safe\x7fname")

    failures = []
    for payload in malicious:
        proc = run_sanitizer(payload)
        if proc.returncode != 1:
            failures.append((payload, proc.returncode))

    assert not failures, "Sanitizer did not exit 1 for malicious inputs: " + ", ".join(
        f"{payload!r} (exit {code})" for payload, code in failures
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
