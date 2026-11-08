#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import random
import secrets
import struct
import subprocess
import tempfile
import uuid

import pytest

EXECUTABLE = "/home/user/config_filter"
SOURCE = "/home/user/config_filter.c"
VIDEO = "/app/config_session.mp4"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"


def run_filter(path):
    return subprocess.run([EXECUTABLE, path], capture_output=True, timeout=10).returncode


def video_iframe_count():
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_frames", "-show_entries", "frame=key_frame",
            "-of", "json", VIDEO,
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=30,
    )
    frames = json.loads(result.stdout).get("frames", [])
    count = sum(int(frame.get("key_frame", 0)) == 1 for frame in frames)
    assert 0 < count <= 0xFFFF, f"Invalid I-frame count derived from {VIDEO}: {count}"
    return count


def make_chunk(magic, version, encoding, payload):
    raw = magic + struct.pack("<H", version) + struct.pack("<H", encoding) + payload
    return gzip.compress(raw)


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile the C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    assert os.path.isfile(SOURCE), f"C source {SOURCE} does not exist."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled executable."


def test_corpus_filtering():
    if not os.path.isfile(EXECUTABLE):
        pytest.fail(f"Executable {EXECUTABLE} missing.")

    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]

    assert len(clean_files) > 0, "No files found in clean corpus."
    assert len(evil_files) > 0, "No files found in evil corpus."

    clean_failed = []
    for f in clean_files:
        res = subprocess.run([EXECUTABLE, f], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(f))

    evil_failed = []
    for f in evil_files:
        res = subprocess.run([EXECUTABLE, f], capture_output=True)
        if res.returncode != 1:
            evil_failed.append(os.path.basename(f))

    error_msgs = []
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: " + ", ".join(evil_failed))
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: " + ", ".join(clean_failed))

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_generated_configuration_chunks():
    k = video_iframe_count()
    nonce = secrets.token_hex(24).encode("ascii")
    wrong_version = k + 1 if k < 0xFFFF else k - 1

    cases = [
        (make_chunk(b"CFG!", k, 0, b"SESSION=" + nonce + b";UPDATE=enabled"), 0, "valid ASCII"),
        (make_chunk(b"CFG!", k, 1, ("SESSION=" + nonce.decode("ascii") + ";UPDATE").encode("utf-16le")), 0, "valid UTF-16LE"),
        (make_chunk(b"CFG!", k, 0, b""), 0, "valid empty payload"),
        (make_chunk(b"BAD!", k, 0, b"SESSION=" + nonce), 1, "wrong magic"),
        (make_chunk(b"CFG!", wrong_version, 0, b"SESSION=" + nonce), 1, "wrong version"),
        (make_chunk(b"CFG!", k, 0, nonce + b"A" * 8191 + b"DROP_TABLE" + b"Z" * 257), 1, "ASCII malicious substring"),
        (make_chunk(b"CFG!", k, 1, (nonce.decode("ascii") + "A" * 4097 + "DROP_TABLE" + "Z" * 31).encode("utf-16le")), 1, "UTF-16LE malicious substring"),
        (make_chunk(b"CFG!", k, 0, b"drop_table DROP-TABLE DROP TABLE " + nonce), 0, "non-exact substrings"),
        (gzip.compress(b"CFG"), 1, "truncated uncompressed header"),
        (b"not-a-gzip-stream-" + secrets.token_bytes(32), 1, "invalid gzip"),
    ]

    valid_then_truncated = make_chunk(b"CFG!", k, 0, b"SESSION=" + nonce)
    cases.append((valid_then_truncated[:-5], 1, "truncated gzip stream"))
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="cfg-verifier-") as directory:
        failures = []
        for contents, expected, description in cases:
            path = os.path.join(directory, uuid.uuid4().hex)
            with open(path, "wb") as f:
                f.write(contents)
            actual = run_filter(path)
            if actual != expected:
                failures.append(f"{description}: expected {expected}, got {actual}")

        assert not failures, "Generated-case failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
