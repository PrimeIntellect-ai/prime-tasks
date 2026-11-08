#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import pytest

HASher_SOURCE = '/home/user/hasher.c'
HASher_BINARY = '/home/user/hasher'
MANIFEST = '/home/user/manifest.txt'


def test_hasher_c_exists():
    assert os.path.isfile('/home/user/hasher.c'), "/home/user/hasher.c does not exist."


def test_hasher_executable_exists():
    assert os.path.isfile('/home/user/hasher'), "/home/user/hasher does not exist."
    assert os.access('/home/user/hasher', os.X_OK), "/home/user/hasher is not executable."
    with open('/home/user/hasher', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/home/user/hasher is not a compiled ELF executable."


def test_manifest_content():
    manifest_path = '/home/user/manifest.txt'
    assert os.path.isfile(manifest_path), f"{manifest_path} does not exist."

    with open(manifest_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_lines = [
        "18 log_b.txt",
        "52 log_d.txt"
    ]

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert lines == expected_lines, f"Manifest content is incorrect. Expected {expected_lines}, got {lines}"


def test_archive_content():
    archive_path = '/home/user/archive.bin'
    assert os.path.isfile(archive_path), f"{archive_path} does not exist."

    with open(archive_path, 'rb') as f:
        content = f.read()

    expected_content = b"Warning: Low disk space.Error code 0x88F."
    assert content == expected_content, f"Archive content is incorrect. Expected {expected_content}, got {content}"


@pytest.fixture(scope='module')
def compiled_source_binary():
    with tempfile.TemporaryDirectory(prefix='hasher-test-') as directory:
        output = os.path.join(directory, 'hasher-from-source')
        result = subprocess.run(
            ['gcc', '-std=c11', HASher_SOURCE, '-o', output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            "The submitted hasher.c does not compile with gcc:\n" +
            result.stderr.decode('utf-8', errors='replace')
        )
        assert os.path.isfile(output) and os.access(output, os.X_OK)
        with open(output, 'rb') as f:
            assert f.read(4) == b'\x7fELF'
        yield output


def _manifest_bytes():
    with open(MANIFEST, 'rb') as f:
        return f.read()


def _restore_manifest(content):
    with open(MANIFEST, 'wb') as f:
        f.write(content)


def _check_valid_invocation(binary, payload, filename):
    before = _manifest_bytes()
    try:
        result = subprocess.run(
            [binary, filename],
            input=payload,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"{binary} failed for a valid invocation: "
            f"{result.stderr.decode('utf-8', errors='replace')}"
        )
        assert result.stdout == payload, "Hasher did not copy stdin to stdout byte-for-byte."

        checksum = 0
        for byte in payload:
            checksum ^= byte
        expected = before + f"{checksum:02X} {filename}\n".encode('utf-8')
        assert _manifest_bytes() == expected, (
            "Hasher did not append exactly the required checksum and filename line."
        )
    finally:
        _restore_manifest(before)


def _check_invalid_invocation(binary, arguments):
    before = _manifest_bytes()
    try:
        result = subprocess.run(
            [binary] + arguments,
            input=secrets.token_bytes(97),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert result.returncode != 0, "Hasher must reject invocations without exactly one argument."
        assert _manifest_bytes() == before, "Invalid invocation modified the manifest."
    finally:
        _restore_manifest(before)


def test_hasher_behavior_and_submitted_source(compiled_source_binary):
    binaries = [HASher_BINARY, compiled_source_binary]
    payloads = [
        b'',
        bytes(range(256)) + secrets.token_bytes(1021),
        secrets.token_bytes(262144 + 37),
    ]

    for binary in binaries:
        for index, payload in enumerate(payloads):
            filename = f"dynamic_{secrets.token_hex(8)}_{index}.txt"
            _check_valid_invocation(binary, payload, filename)
        _check_invalid_invocation(binary, [])
        _check_invalid_invocation(binary, ['one.txt', 'two.txt'])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
