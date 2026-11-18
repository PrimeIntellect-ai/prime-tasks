#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import struct
import subprocess
import tempfile


def test_libwalrec_builds_successfully():
    """Verify that the vendored package builds successfully after fixing the Makefile."""
    build_dir = "/app/libwalrec"

    subprocess.run(["make", "clean"], cwd=build_dir, capture_output=True)
    result = subprocess.run(["make"], cwd=build_dir, capture_output=True, text=True)

    assert result.returncode == 0, f"make failed in {build_dir}. Output: {result.stderr}"

    archive_path = os.path.join(build_dir, "libwalrec.a")
    assert os.path.isfile(archive_path), f"Expected build artifact {archive_path} was not created."


def test_wal_sanitizer_adversarial_corpus():
    """Retain the original corpus checks."""
    sanitizer_bin = "/home/user/wal_sanitizer"

    assert os.path.isfile(sanitizer_bin), f"Sanitizer binary not found at {sanitizer_bin}"
    assert os.access(sanitizer_bin, os.X_OK), f"Sanitizer at {sanitizer_bin} is not executable."

    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    bypassed_evil = []
    for filepath in evil_files:
        result = subprocess.run([sanitizer_bin, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed_evil.append(os.path.basename(filepath))

    modified_clean = []
    for filepath in clean_files:
        result = subprocess.run([sanitizer_bin, filepath], capture_output=True)
        if result.returncode != 0:
            modified_clean.append(os.path.basename(filepath))

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_msgs.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")

    assert not error_msgs, " | ".join(error_msgs)


def _write_wal(path, records):
    with open(path, "wb") as f:
        f.write(b"WAL1")
        for record_type, payload in records:
            f.write(struct.pack("<BH", record_type, len(payload)))
            f.write(payload)


def _expected_status(records):
    return 1 if any(record_type == 0x42 and len(payload) > 512 for record_type, payload in records) else 0


def _safe_record(rng):
    record_type = rng.randrange(256)
    if record_type == 0x42:
        length = rng.randrange(513)
    else:
        length = rng.randrange(2049)
    return record_type, os.urandom(length)


def test_wal_sanitizer_generated_wals():
    """Exercise newly generated WALs whose expected result is derived from their records."""
    sanitizer_bin = "/home/user/wal_sanitizer"
    assert os.path.isfile(sanitizer_bin), f"Sanitizer binary not found at {sanitizer_bin}"
    assert os.access(sanitizer_bin, os.X_OK), f"Sanitizer at {sanitizer_bin} is not executable."

    rng = random.SystemRandom()
    cases = [
        [(0x42, os.urandom(511))],
        [(0x42, os.urandom(512))],
        [(0x42, os.urandom(513))],
        [(0x10, os.urandom(4096))],
        [(0x10, os.urandom(31)), (0x42, os.urandom(513))],
        [(0x42, os.urandom(512)), (0x20, os.urandom(19)), (0x42, os.urandom(514))],
    ]

    # Create matched safe/vulnerable pairs with identical record lengths and
    # vulnerability positions varying throughout the WAL. Random payloads also
    # contain incidental byte patterns, requiring traversal of actual records.
    for _ in range(18):
        base = [_safe_record(rng) for _ in range(rng.randrange(1, 7))]
        position = rng.randrange(len(base) + 1)
        length = rng.randrange(513, 4097)
        safe_type = rng.choice([t for t in range(256) if t != 0x42])

        safe_records = list(base)
        safe_records.insert(position, (safe_type, os.urandom(length)))
        vulnerable_records = list(base)
        vulnerable_records.insert(position, (0x42, os.urandom(length)))
        cases.extend([safe_records, vulnerable_records])

    # Explicitly require processing through the final record.
    cases.append([_safe_record(rng) for _ in range(6)] + [(0x42, os.urandom(513))])
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="walcheck-") as temp_dir:
        generated = []
        for records in cases:
            path = os.path.join(temp_dir, secrets.token_hex(16) + ".dat")
            _write_wal(path, records)
            generated.append((path, _expected_status(records)))

        rng.shuffle(generated)
        for path, expected in generated:
            try:
                result = subprocess.run([sanitizer_bin, path], capture_output=True, timeout=5)
                actual = result.returncode
            except subprocess.TimeoutExpired:
                actual = "timeout"
            if actual != expected:
                failures.append(f"{os.path.basename(path)} expected {expected}, got {actual}")

    assert not failures, "Generated WAL failures: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
