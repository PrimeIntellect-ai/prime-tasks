#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import gzip
import os
import random
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = "/home/user/artifact_filter"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
XOR_KEY = 42


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "artifact_filter is not a compiled ELF binary."
    result = subprocess.run(
        ["go", "version", "-m", BINARY_PATH], capture_output=True, text=True
    )
    assert result.returncode == 0 and "go1." in (result.stdout + result.stderr), \
        "artifact_filter is not a Go executable."


def encode_artifact(magic, log, artifact_data, extra_header=b""):
    assert len(magic) == 4
    assert len(extra_header) <= 60
    header = magic + extra_header + os.urandom(60 - len(extra_header))
    payload = header + log.encode("utf-8") + b"\n---END_LOG---\n" + artifact_data
    compressed = gzip.compress(payload)
    return bytes(byte ^ XOR_KEY for byte in compressed)


def test_generated_mixed_adversarial_corpus():
    # All labels are mixed in one randomly named directory, and neither filenames
    # nor directory names disclose the expected classification.
    corpus_dir = tempfile.mkdtemp(prefix="artifact-input-", dir="/tmp")
    cases = [
        (b"\x00\x11\x22\x33", "AUTHORIZATION: VALID\nDATE: 2026-09-11", os.urandom(80), "CLEAN"),
        (b"\xDE\xAD\xBE\xEF", "AUTHORIZATION: VALID\nDETAIL: ordinary", os.urandom(91), "EVIL"),
        (b"\x01\x02\x03\x04", "USER: tester\nAUTHORIZATION: BYPASS\nDATE: today", os.urandom(73), "EVIL"),
        (b"\x10\x20\x30\x40", "PREFIX AUTHORIZATION: BYPASS SUFFIX\nSECOND: line", os.urandom(64), "EVIL"),
        # Trigger text in artifact data, after the log delimiter, must not affect classification.
        (b"\x55\x66\x77\x88", "AUTHORIZATION: VALID\nSTATUS: OK", b"AUTHORIZATION: BYPASS\x00" + os.urandom(45), "CLEAN"),
        # Evil magic appearing later in the header must not affect classification.
        (b"\x12\x34\x56\x78", "AUTHORIZATION: VALID\nSTATUS: OK", os.urandom(52), "CLEAN"),
    ]
    random.SystemRandom().shuffle(cases)

    expected_lines = []
    originals = {}
    expected_destinations = {}
    for magic, log, data, label in cases:
        filename = f"{secrets.token_hex(8)}.bin"
        extra_header = b"\xDE\xAD\xBE\xEF" if label == "CLEAN" and magic != b"\xDE\xAD\xBE\xEF" else b""
        encoded = encode_artifact(magic, log, data, extra_header)
        source = os.path.join(corpus_dir, filename)
        with open(source, "wb") as f:
            f.write(encoded)
        originals[source] = encoded
        suffix = ".evil" if label == "EVIL" else ".clean"
        expected_destinations[source] = source + suffix
        expected_lines.append(f"[{filename}]: {label}")

    result = subprocess.run([BINARY_PATH, corpus_dir], capture_output=True, text=True)
    assert result.returncode == 0, f"Binary execution failed on generated corpus: {result.stderr}"

    actual_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert collections.Counter(actual_lines) == collections.Counter(expected_lines), \
        f"Unexpected classification output. Expected {expected_lines}, got {actual_lines}"

    for source, destination in expected_destinations.items():
        assert not os.path.exists(source), f"Processed source was not renamed: {source}"
        assert os.path.isfile(destination), f"Expected renamed file is missing: {destination}"
        with open(destination, "rb") as f:
            assert f.read() == originals[source], f"Renaming changed file contents: {destination}"


def check_fixed_corpus(corpus_dir, expected_label):
    initial_files = [f for f in os.listdir(corpus_dir) if f.endswith(".bin")]
    assert len(initial_files) > 0, f"No .bin files found in {corpus_dir} before execution."

    result = subprocess.run([BINARY_PATH, corpus_dir], capture_output=True, text=True)
    assert result.returncode == 0, f"Binary execution failed on {corpus_dir}: {result.stderr}"
    stdout_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]

    failed_files = []
    suffix = ".clean" if expected_label == "CLEAN" else ".evil"
    for filename in initial_files:
        expected_output = f"[{filename}]: {expected_label}"
        if expected_output not in stdout_lines:
            failed_files.append(filename)
        expected_renamed_path = os.path.join(corpus_dir, filename + suffix)
        if not os.path.isfile(expected_renamed_path):
            failed_files.append(filename)

    if failed_files:
        pytest.fail(
            f"{len(set(failed_files))} of {len(initial_files)} files in {corpus_dir} "
            f"were not classified/renamed as {expected_label}: {', '.join(set(failed_files))}"
        )


def test_clean_corpus():
    check_fixed_corpus(CLEAN_CORPUS_DIR, "CLEAN")


def test_evil_corpus():
    check_fixed_corpus(EVIL_CORPUS_DIR, "EVIL")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
