#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import os
import random
import secrets
import string
import subprocess
import tarfile
import tempfile

import pytest

SCRIPT_PATH = "/home/user/artifact_filter.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
WATERMARK = b"MALWARE_X99_PAYLOAD"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable"


def test_clean_corpus():
    if not os.path.exists(CLEAN_CORPUS_DIR):
        pytest.skip(f"Clean corpus directory {CLEAN_CORPUS_DIR} does not exist.")

    artifacts = [d for d in os.listdir(CLEAN_CORPUS_DIR) if os.path.isdir(os.path.join(CLEAN_CORPUS_DIR, d))]
    if not artifacts:
        pytest.skip(f"No artifacts found in {CLEAN_CORPUS_DIR}.")

    failed_artifacts = []

    for artifact in artifacts:
        artifact_path = os.path.join(CLEAN_CORPUS_DIR, artifact)
        result = subprocess.run([SCRIPT_PATH, artifact_path], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "CLEAN":
            failed_artifacts.append((artifact, output))

    if failed_artifacts:
        summary = f"{len(failed_artifacts)} of {len(artifacts)} clean modified/rejected. "
        details = ", ".join([f"{a} (output: {o})" for a, o in failed_artifacts])
        pytest.fail(f"{summary}Offending artifacts: {details}")


def test_evil_corpus():
    if not os.path.exists(EVIL_CORPUS_DIR):
        pytest.skip(f"Evil corpus directory {EVIL_CORPUS_DIR} does not exist.")

    artifacts = [d for d in os.listdir(EVIL_CORPUS_DIR) if os.path.isdir(os.path.join(EVIL_CORPUS_DIR, d))]
    if not artifacts:
        pytest.skip(f"No artifacts found in {EVIL_CORPUS_DIR}.")

    failed_artifacts = []

    for artifact in artifacts:
        artifact_path = os.path.join(EVIL_CORPUS_DIR, artifact)
        result = subprocess.run([SCRIPT_PATH, artifact_path], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "EVIL":
            failed_artifacts.append((artifact, output))

    if failed_artifacts:
        summary = f"{len(failed_artifacts)} of {len(artifacts)} evil bypassed. "
        details = ", ".join([f"{a} (output: {o})" for a, o in failed_artifacts])
        pytest.fail(f"{summary}Offending artifacts: {details}")


def random_text(length=4096):
    alphabet = string.ascii_letters + string.digits + " \n"
    return "".join(secrets.choice(alphabet) for _ in range(length)).encode()


def make_tar(files):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w") as archive:
        for name, data in files.items():
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            info.mode = 0o644
            info.mtime = 0
            archive.addfile(info, io.BytesIO(data))
    return stream.getvalue()


def make_archive(files):
    return gzip.compress(make_tar(files), compresslevel=6, mtime=0)


def suffix_for(index):
    return chr(ord("a") + index // 26) + chr(ord("a") + index % 26)


def write_chunks(directory, blob):
    os.makedirs(directory)
    chunk_size = secrets.randbelow(53) + 31
    chunks = [blob[i:i + chunk_size] for i in range(0, len(blob), chunk_size)]
    # Create them in a non-alphabetical order so directory insertion order cannot
    # substitute for sorting the sequential chunk names.
    indices = list(range(len(chunks)))
    random.SystemRandom().shuffle(indices)
    for i in indices:
        with open(os.path.join(directory, "chunk_" + suffix_for(i)), "wb") as handle:
            handle.write(chunks[i])


def test_generated_artifacts_without_labeled_paths():
    clean_one = make_archive({
        "docs/readme.txt": b"ordinary repository documentation\n" + random_text(),
        "notes/info.txt": b"no prohibited content here\n",
    })
    clean_two = make_archive({
        "nested/deeper/message.txt": random_text(),
        "top.txt": b"another intact artifact\n",
    })

    utf8_malicious = make_archive({
        "data/report.txt": random_text(700) + b"\n" + WATERMARK + b"\n",
        "data/decoy.txt": random_text(),
    })
    utf16le_malicious = make_archive({
        "content/localized.txt": (b"prefix " + WATERMARK + b" suffix").decode().encode("utf-16le"),
        "content/decoy.txt": random_text(),
    })

    trailing = make_archive({"file.txt": random_text()}) + b"TRAILING-GARBAGE-" + secrets.token_bytes(19)

    bad_checksum = bytearray(make_archive({"file.txt": random_text()}))
    bad_checksum[-8] ^= 1

    valid_tar = bytearray(make_tar({"file.txt": random_text()}))
    valid_tar[0] ^= 1  # invalidate the tar header checksum, then recompress correctly
    bad_tar = gzip.compress(bytes(valid_tar), compresslevel=6, mtime=0)

    truncated_source = make_archive({"file.txt": random_text()})
    truncated = truncated_source[:-secrets.randbelow(16) - 9]

    cases = [
        (clean_one, "CLEAN"),
        (clean_two, "CLEAN"),
        (utf8_malicious, "EVIL"),
        (utf16le_malicious, "EVIL"),
        (trailing, "EVIL"),
        (bytes(bad_checksum), "EVIL"),
        (bad_tar, "EVIL"),
        (truncated, "EVIL"),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="artifact-batch-") as root:
        generated = []
        for blob, expected in cases:
            path = os.path.join(root, secrets.token_hex(12))
            write_chunks(path, blob)
            generated.append((path, expected))

        failures = []
        for path, expected in generated:
            try:
                result = subprocess.run(
                    [SCRIPT_PATH, path], capture_output=True, text=True, timeout=10
                )
                output = result.stdout.strip()
            except subprocess.TimeoutExpired:
                failures.append((os.path.basename(path), expected, "timed out"))
                continue
            if output != expected:
                failures.append((os.path.basename(path), expected, output))

        assert not failures, f"Generated artifact classifications failed: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
