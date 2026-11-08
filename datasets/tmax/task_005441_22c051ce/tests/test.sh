#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile

import pytest

SANITISER = "/home/user/sanitiser"
SOURCE = "/home/user/sanitiser.cpp"


def run_filter(path, content):
    result = subprocess.run(
        [path], input=content, capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}; stderr={result.stderr!r}"
    )
    return result.stdout


@pytest.fixture(scope="session")
def rebuilt_sanitiser():
    assert os.path.isfile(SOURCE), f"C++ source not found at {SOURCE}"

    build_dir = tempfile.mkdtemp(prefix="sanitiser-build-")
    rebuilt = os.path.join(build_dir, "sanitiser")
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", rebuilt],
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Failed to compile {SOURCE} as C++: {result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
    yield rebuilt


def test_sanitiser_exists_and_executable():
    assert os.path.isfile(SANITISER), f"Sanitiser executable not found at {SANITISER}"
    assert os.access(SANITISER, os.X_OK), f"Sanitiser at {SANITISER} is not executable"
    with open(SANITISER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitiser must be a compiled executable"


def test_cpp_source_exists_and_builds(rebuilt_sanitiser):
    assert os.path.isfile(SOURCE), f"C++ source not found at {SOURCE}"
    with open(rebuilt_sanitiser, "rb") as f:
        assert f.read(4) == b"\x7fELF"


def test_sanitiser_clean_corpus():
    clean_dir = "/app/corpora/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} not found"

    clean_files = [
        os.path.join(clean_dir, f)
        for f in os.listdir(clean_dir)
        if os.path.isfile(os.path.join(clean_dir, f))
    ]
    assert len(clean_files) > 0, "No clean corpus files found"

    failed_files = []
    for file_path in clean_files:
        with open(file_path, "rb") as f:
            content = f.read()
        if run_filter(SANITISER, content) != content:
            failed_files.append(os.path.basename(file_path))

    assert not failed_files, (
        f"{len(failed_files)} of {len(clean_files)} clean modified: "
        + ", ".join(failed_files)
    )


def test_sanitiser_evil_corpus():
    evil_dir = "/app/corpora/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} not found"

    evil_files = [
        os.path.join(evil_dir, f)
        for f in os.listdir(evil_dir)
        if os.path.isfile(os.path.join(evil_dir, f))
    ]
    assert len(evil_files) > 0, "No evil corpus files found"

    failed_files = []
    for file_path in evil_files:
        with open(file_path, "rb") as f:
            content = f.read()
        if run_filter(SANITISER, content) != b"":
            failed_files.append(os.path.basename(file_path))

    assert not failed_files, (
        f"{len(failed_files)} of {len(evil_files)} evil bypassed: "
        + ", ".join(failed_files)
    )


def random_token(length):
    alphabet = string.ascii_uppercase + string.digits + "_"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def test_randomised_crash_pattern_and_mixed_stream(rebuilt_sanitiser):
    cases = []

    # A 15-byte application name fits with its NUL terminator; 16 bytes does not.
    for length, malicious in [(1, False), (15, False), (16, True), (17, True), (64, True)]:
        name = random_token(length)
        line = f"[{random_token(20)}] [{name}] {random_token(24)}\n".encode()
        cases.append((line, malicious))

    for _ in range(100):
        malicious = bool(secrets.randbits(1))
        length = secrets.randbelow(80) + 16 if malicious else secrets.randbelow(15) + 1
        name = random_token(length)
        line = f"[{random_token(20)}] [{name}] {random_token(32)}\n".encode()
        cases.append((line, malicious))

    # Lines without the parsed application-name field are benign and must survive.
    for _ in range(10):
        cases.append((f"plain-log-{random_token(30)}\n".encode(), False))

    random.SystemRandom().shuffle(cases)
    input_data = b"".join(line for line, _ in cases)
    expected = b"".join(line for line, malicious in cases if not malicious)

    for candidate in (SANITISER, rebuilt_sanitiser):
        assert run_filter(candidate, input_data) == expected, (
            f"{candidate} did not correctly filter a random mixed log stream"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
