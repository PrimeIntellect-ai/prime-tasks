#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import secrets
import struct
import subprocess
import tempfile
import uuid

import pytest

CLEAN_DIR = "/home/user/dataset/clean/"
EVIL_DIR = "/home/user/dataset/evil/"
SANITIZER_SOURCE = "/home/user/sanitizer.c"
SANITIZER_BIN = "/home/user/sanitizer"
EXTRACTED_DIR = "/home/user/dataset/extracted/"
MANIFEST_FILE = "/home/user/dataset/manifest.txt"


def parse_darc(filepath):
    """Parses the DARC archive format and returns a list of (path, data) tuples."""
    files = []
    with open(filepath, 'rb') as f:
        data = f.read()

    if not data.startswith(b'DARC'):
        return files

    offset = 4
    if offset + 2 > len(data):
        return files

    file_count = struct.unpack_from('<H', data, offset)[0]
    offset += 2

    for _ in range(file_count):
        if offset + 2 > len(data):
            break
        path_len = struct.unpack_from('<H', data, offset)[0]
        offset += 2

        if offset + path_len > len(data):
            break
        path = data[offset:offset+path_len].decode('utf-8', errors='replace')
        offset += path_len

        if offset + 4 > len(data):
            break
        file_size = struct.unpack_from('<I', data, offset)[0]
        offset += 4

        if offset + file_size > len(data):
            break
        file_data = data[offset:offset+file_size]
        offset += file_size

        files.append((path, file_data))

    return files


def make_darc(entries):
    result = bytearray(b'DARC')
    result += struct.pack('<H', len(entries))
    for path, payload in entries:
        path_bytes = path.encode('utf-8')
        result += struct.pack('<H', len(path_bytes))
        result += path_bytes
        result += struct.pack('<I', len(payload))
        result += payload
    return bytes(result)


def run_sanitizer(binary, archive, *extra_args):
    try:
        return subprocess.run(
            [binary, archive, *extra_args],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitizer timed out on {archive}")


@pytest.fixture(scope='session')
def rebuilt_sanitizer():
    assert os.path.exists(SANITIZER_SOURCE), f"C source not found at {SANITIZER_SOURCE}"
    assert os.path.isfile(SANITIZER_SOURCE), f"{SANITIZER_SOURCE} is not a file"
    output = os.path.join(tempfile.gettempdir(), f"rebuilt-sanitizer-{uuid.uuid4().hex}")
    try:
        build = subprocess.run(
            ['gcc', '-O2', SANITIZER_SOURCE, '-o', output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Compilation of sanitizer.c timed out")
    assert build.returncode == 0, (
        "sanitizer.c did not compile as C:\n" +
        build.stderr.decode('utf-8', errors='replace')[-4000:]
    )
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    yield output
    try:
        os.unlink(output)
    except FileNotFoundError:
        pass


def test_sanitizer_exists():
    assert os.path.exists(SANITIZER_BIN), f"Sanitizer binary not found at {SANITIZER_BIN}"
    assert os.path.isfile(SANITIZER_BIN), f"{SANITIZER_BIN} is not a file"
    assert os.access(SANITIZER_BIN, os.X_OK), f"Sanitizer binary at {SANITIZER_BIN} is not executable"
    with open(SANITIZER_BIN, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Sanitizer executable must be a compiled native binary"


def test_sanitizer_source_builds(rebuilt_sanitizer):
    with open(rebuilt_sanitizer, 'rb') as f:
        assert f.read(4) == b'\x7fELF'


def test_sanitizer_on_corpora():
    evil_bypassed = []
    clean_rejected = []

    if os.path.exists(EVIL_DIR):
        for filename in os.listdir(EVIL_DIR):
            filepath = os.path.join(EVIL_DIR, filename)
            if not os.path.isfile(filepath):
                continue
            result = subprocess.run([SANITIZER_BIN, filepath], capture_output=True)
            if result.returncode != 1:
                evil_bypassed.append(filename)

    if os.path.exists(CLEAN_DIR):
        for filename in os.listdir(CLEAN_DIR):
            filepath = os.path.join(CLEAN_DIR, filename)
            if not os.path.isfile(filepath):
                continue
            result = subprocess.run([SANITIZER_BIN, filepath], capture_output=True)
            if result.returncode != 0:
                clean_rejected.append(filename)

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} evil archives bypassed sanitizer (expected exit code 1): {evil_bypassed[:5]}")
    if clean_rejected:
        error_msg.append(f"{len(clean_rejected)} clean archives rejected by sanitizer (expected exit code 0): {clean_rejected[:5]}")

    assert not evil_bypassed and not clean_rejected, " | ".join(error_msg)


def test_sanitizer_on_novel_archives(rebuilt_sanitizer, tmp_path):
    archive = tmp_path / f"sample-{uuid.uuid4().hex}.bin"
    token = secrets.token_hex(8)
    payload = secrets.token_bytes(37)

    safe_paths = [
        f"logs/{token}/sensor.log",
        f"..hidden-{token}.log",
        f"nested/.../{token}.log",
        f"nested/..safe-{token}.log",
    ]
    bad_paths = [
        f"../outside-{token}",
        f"nested/../outside-{token}",
        f"deep/one/../../outside-{token}",
        f"/tmp/absolute-{token}",
    ]

    cases = [
        (make_darc([]), 0),
        (make_darc([(safe_paths[0], payload)]), 0),
        (make_darc([(p, secrets.token_bytes(11)) for p in safe_paths]), 0),
        (make_darc([(safe_paths[0], b''), (safe_paths[1], payload)]), 0),
    ]
    for bad in bad_paths:
        cases.append((make_darc([(safe_paths[0], payload), (bad, b'x'), (safe_paths[1], b'y')]), 1))

    random.SystemRandom().shuffle(cases)
    for binary in (SANITIZER_BIN, rebuilt_sanitizer):
        for contents, expected in cases:
            archive.write_bytes(contents)
            actual = run_sanitizer(binary, str(archive))
            assert actual == expected, (
                f"{binary} returned {actual}, expected {expected}, for a novel DARC archive"
            )


def test_sanitizer_rejects_malformed_without_crashing(rebuilt_sanitizer, tmp_path):
    archive = tmp_path / f"input-{uuid.uuid4().hex}.darc"
    malformed = [
        b'',
        b'DAR',
        b'NOPE' + struct.pack('<H', 0),
        b'DARC',
        b'DARC' + struct.pack('<H', 1),
        b'DARC' + struct.pack('<H', 1) + struct.pack('<H', 12) + b'abc',
        b'DARC' + struct.pack('<H', 1) + struct.pack('<H', 3) + b'abc',
        b'DARC' + struct.pack('<H', 1) + struct.pack('<H', 3) + b'abc' + struct.pack('<I', 100) + b'x',
        b'DARC' + struct.pack('<H', 65535),
    ]
    random.SystemRandom().shuffle(malformed)

    for binary in (SANITIZER_BIN, rebuilt_sanitizer):
        for contents in malformed:
            archive.write_bytes(contents)
            actual = run_sanitizer(binary, str(archive))
            assert actual > 0, (
                f"{binary} must reject malformed input without crashing; return code was {actual}"
            )

        no_arg = subprocess.run(
            [binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3
        ).returncode
        two_args = subprocess.run(
            [binary, str(archive), str(archive)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        ).returncode
        assert no_arg > 0, f"{binary} accepted invocation with no archive argument"
        assert two_args > 0, f"{binary} accepted invocation with more than one argument"


def test_extracted_files_and_manifest():
    assert os.path.exists(EXTRACTED_DIR), f"Extracted directory not found at {EXTRACTED_DIR}"
    assert os.path.isdir(EXTRACTED_DIR), f"{EXTRACTED_DIR} is not a directory"
    assert os.path.exists(MANIFEST_FILE), f"Manifest file not found at {MANIFEST_FILE}"

    expected_files = {}
    expected_manifest_lines = set()

    for filename in os.listdir(CLEAN_DIR):
        filepath = os.path.join(CLEAN_DIR, filename)
        if not os.path.isfile(filepath):
            continue

        parsed_files = parse_darc(filepath)
        for path, data in parsed_files:
            file_hash = hashlib.sha256(data).hexdigest()
            expected_files[f"{file_hash}.log"] = data
            expected_manifest_lines.add(f"{file_hash} {path}")

    actual_files = set(os.listdir(EXTRACTED_DIR))
    expected_filenames = set(expected_files.keys())

    missing_files = expected_filenames - actual_files
    extra_files = actual_files - expected_filenames

    assert not missing_files, f"Missing extracted files: {list(missing_files)[:5]}"
    assert not extra_files, f"Extra files found in extracted directory: {list(extra_files)[:5]}"

    for filename, expected_data in expected_files.items():
        filepath = os.path.join(EXTRACTED_DIR, filename)
        with open(filepath, 'rb') as f:
            actual_data = f.read()
        assert actual_data == expected_data, f"Data mismatch in extracted file: {filename}"

    with open(MANIFEST_FILE, 'r', encoding='utf-8') as f:
        actual_manifest_lines = set(line.strip() for line in f if line.strip())

    missing_manifest = expected_manifest_lines - actual_manifest_lines
    extra_manifest = actual_manifest_lines - expected_manifest_lines

    assert not missing_manifest, f"Missing entries in manifest: {list(missing_manifest)[:5]}"
    assert not extra_manifest, f"Extra entries in manifest: {list(extra_manifest)[:5]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
