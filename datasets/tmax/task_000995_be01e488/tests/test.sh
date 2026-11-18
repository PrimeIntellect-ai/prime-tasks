#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import struct
import subprocess
import tempfile
import zlib

import pytest

SOURCE = "/home/user/extractor.c"
BINARY = "/home/user/extractor"
REPO = "/home/user/artifact_repo"
EXTRACTED = "/home/user/extracted_artifacts"
MANIFEST = "/home/user/manifest.txt"


def read_cbnd(path):
    with open(path, "rb") as f:
        data = f.read()

    assert data[:4] == b"CBND", f"Invalid test bundle magic: {path}"
    count = struct.unpack_from("<I", data, 4)[0]
    files = {}
    for i in range(count):
        pos = 8 + i * 76
        raw_name, compressed_size, uncompressed_size, offset = struct.unpack_from(
            "<64sIII", data, pos
        )
        name = raw_name.split(b"\0", 1)[0].decode("ascii")
        content = zlib.decompress(data[offset:offset + compressed_size])
        assert len(content) == uncompressed_size
        files[name] = content
    return files


def create_cbnd(path, files):
    index = bytearray()
    payload = bytearray()
    offset = 8 + 76 * len(files)
    for name, content in files:
        compressed = zlib.compress(content)
        encoded = name.encode("ascii")
        index.extend(encoded + b"\0" * (64 - len(encoded)))
        index.extend(struct.pack("<III", len(compressed), len(content), offset))
        payload.extend(compressed)
        offset += len(compressed)

    with open(path, "wb") as f:
        f.write(b"CBND")
        f.write(struct.pack("<I", len(files)))
        f.write(index)
        f.write(payload)


def repository_bundles():
    result = []
    for root, _, names in os.walk(REPO):
        for name in names:
            if name.endswith(".cbnd"):
                result.append(os.path.join(root, name))
    return sorted(result)


def run_and_verify(executable, bundle, expected):
    with tempfile.TemporaryDirectory(prefix="cbnd-output-") as output:
        completed = subprocess.run(
            [executable, bundle, output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert completed.returncode == 0, (
            f"Extractor failed for {bundle}: "
            f"{completed.stderr.decode(errors='replace')}"
        )
        for name, content in expected.items():
            path = os.path.join(output, name)
            assert os.path.isfile(path), f"Extractor did not create {name}"
            with open(path, "rb") as f:
                assert f.read() == content, f"Extractor produced incorrect data for {name}"


@pytest.fixture(scope="session")
def rebuilt_extractor():
    output = os.path.join(tempfile.mkdtemp(prefix="rebuilt-extractor-"), "extractor")
    completed = subprocess.run(
        ["gcc", SOURCE, "-o", output, "-lz"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert completed.returncode == 0, (
        "extractor.c does not compile: " + completed.stderr.decode(errors="replace")
    )
    return output


def test_extractor_files_exist():
    assert os.path.isfile(SOURCE), f"Source file missing: {SOURCE}"
    assert os.path.isfile(BINARY), f"Compiled binary missing: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Extractor binary is not executable: {BINARY}"


def test_extractors_process_repository_and_unseen_bundle(rebuilt_extractor):
    bundles = repository_bundles()
    assert bundles, "No CBND bundles found in the repository"

    for bundle in bundles:
        expected = read_cbnd(bundle)
        run_and_verify(BINARY, bundle, expected)
        run_and_verify(rebuilt_extractor, bundle, expected)

    with tempfile.TemporaryDirectory(prefix="cbnd-input-") as tempdir:
        challenge = os.path.join(tempdir, "challenge.cbnd")
        challenge_files = {
            "dynamic_one.dat": secrets.token_bytes(137),
            "dynamic_two.bin": secrets.token_bytes(4097),
        }
        create_cbnd(challenge, list(challenge_files.items()))
        run_and_verify(BINARY, challenge, challenge_files)
        run_and_verify(rebuilt_extractor, challenge, challenge_files)


def test_extracted_files_exist_and_correct():
    assert os.path.isdir(EXTRACTED), f"Extracted artifacts directory missing: {EXTRACTED}"

    expected = {}
    for bundle in repository_bundles():
        expected.update(read_cbnd(bundle))

    for name, content in expected.items():
        path = os.path.join(EXTRACTED, name)
        assert os.path.isfile(path), f"Extracted file missing: {path}"
        with open(path, "rb") as f:
            assert f.read() == content, f"Content mismatch for extracted file: {name}"


def test_manifest_matches_expected():
    assert os.path.isfile(MANIFEST), f"Manifest file not found at {MANIFEST}"

    expected_files = {}
    for bundle in repository_bundles():
        expected_files.update(read_cbnd(bundle))

    expected_lines = [
        f"{hashlib.sha256(content).hexdigest()}  {name}"
        for name, content in sorted(expected_files.items())
    ]

    with open(MANIFEST, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        "Manifest does not have the correct number of entries."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Manifest line {i + 1} mismatch.\nExpected: {expected}\nActual: {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
