#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import string
import struct
import subprocess
import zlib

import pytest

ORACLE_PATH = "/app/doc-archiver-1.0/darc-extract"
AGENT_PATH = "/home/user/my-darc-extract"
SOURCE_DIR = "/app/doc-archiver-1.0"
NUM_TESTS = 100


def generate_random_markdown(length):
    lines = []
    current_len = 0
    while current_len < length:
        start = random.choices(
            ["H1: ", "H2: ", "Normal text ", "  H1: ", "\n"],
            weights=[10, 10, 70, 5, 5],
        )[0]
        line_len = random.randint(10, 100)
        content = ''.join(
            random.choices(string.ascii_letters + string.digits + ' ', k=line_len)
        )
        line = start + content + "\n"
        lines.append(line)
        current_len += len(line)
    return "".join(lines)[:length]


def transform_markdown(data):
    result = bytearray()
    index = 0
    at_line_start = True
    while index < len(data):
        if at_line_start and data.startswith(b"H1:", index):
            result.extend(b"# ")
            index += 3
            at_line_start = False
        elif at_line_start and data.startswith(b"H2:", index):
            result.extend(b"## ")
            index += 3
            at_line_start = False
        else:
            value = data[index]
            result.append(value)
            index += 1
            at_line_start = value == 10
    return bytes(result)


def create_darc_archive(content):
    if isinstance(content, str):
        content = content.encode("utf-8")
    compressed = zlib.compress(content)
    return b"DARC" + struct.pack("<I", len(compressed)) + compressed


def run_program(path, archive, timeout=5):
    try:
        return subprocess.run(
            [path],
            input=archive,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Program {path} timed out")


def file_digest(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.digest()


@pytest.fixture(scope="session")
def rebuilt_oracle():
    assert os.path.exists(ORACLE_PATH), (
        f"Oracle program not found at {ORACLE_PATH}. Did you fix the Makefile and run make?"
    )
    assert os.access(ORACLE_PATH, os.X_OK), (
        f"Oracle program {ORACLE_PATH} is not executable."
    )
    assert os.path.isfile(ORACLE_PATH), f"Oracle path {ORACLE_PATH} is not a file."

    os.unlink(ORACLE_PATH)
    try:
        build = subprocess.run(
            ["make", "-B", "darc-extract"],
            cwd=SOURCE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Building darc-extract timed out")

    assert build.returncode == 0, (
        "Running make did not successfully build darc-extract.\n"
        f"stdout:\n{build.stdout.decode(errors='replace')}\n"
        f"stderr:\n{build.stderr.decode(errors='replace')}"
    )
    assert os.path.exists(ORACLE_PATH), "make did not produce darc-extract"
    assert os.path.isfile(ORACLE_PATH), "make did not produce a regular executable file"
    assert os.access(ORACLE_PATH, os.X_OK), "make produced a non-executable darc-extract"
    return ORACLE_PATH


@pytest.fixture(scope="session")
def setup_fuzz_inputs():
    random.seed(42)
    inputs = []
    for index in range(NUM_TESTS):
        if index < 5:
            size = random.randint(1_000_000, 5_000_000)
        else:
            size = random.randint(100, 10_000)
        content = generate_random_markdown(size).encode("utf-8")
        inputs.append((create_darc_archive(content), transform_markdown(content)))

    edge_contents = [
        b"",
        b"H1:title",
        b"H2:title\nH1:next\nNormal H1: text\n  H2:not a heading\n",
        b"H\nH1\nH2\nH1:\nH2:\n",
        b"A" * 16382 + b"\nH1:cross-boundary\n",
        b"A" * 16383 + b"\nH2:next-chunk\n",
    ]
    for content in edge_contents:
        inputs.append((create_darc_archive(content), transform_markdown(content)))
    return inputs


def test_oracle_exists():
    assert os.path.exists(ORACLE_PATH), (
        f"Oracle program not found at {ORACLE_PATH}. Did you fix the Makefile and run make?"
    )
    assert os.access(ORACLE_PATH, os.X_OK), (
        f"Oracle program {ORACLE_PATH} is not executable."
    )


def test_agent_program_exists():
    assert os.path.exists(AGENT_PATH), f"Agent program not found at {AGENT_PATH}."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program {AGENT_PATH} is not executable."
    assert os.path.isfile(AGENT_PATH), f"Agent path {AGENT_PATH} is not a file."


def test_make_rebuilds_oracle(rebuilt_oracle):
    assert os.path.exists(rebuilt_oracle)
    assert os.access(rebuilt_oracle, os.X_OK)


def test_agent_is_distinct_from_reference(rebuilt_oracle):
    assert not os.path.samefile(AGENT_PATH, rebuilt_oracle), (
        "The standalone implementation must not be the reference executable itself."
    )
    assert file_digest(AGENT_PATH) != file_digest(rebuilt_oracle), (
        "The standalone implementation is byte-identical to the reference executable."
    )


def test_fuzz_equivalence(rebuilt_oracle, setup_fuzz_inputs):
    for index, (darc_data, expected) in enumerate(setup_fuzz_inputs):
        oracle_proc = run_program(rebuilt_oracle, darc_data)
        agent_proc = run_program(AGENT_PATH, darc_data)

        assert oracle_proc.returncode == agent_proc.returncode, (
            f"Return code mismatch on input {index}: "
            f"Oracle={oracle_proc.returncode}, Agent={agent_proc.returncode}"
        )
        assert oracle_proc.returncode == 0, (
            f"Reference failed on valid input {index}: {oracle_proc.stderr[:500]!r}"
        )
        assert oracle_proc.stdout == agent_proc.stdout, (
            f"Output mismatch on valid input {index}: "
            f"Oracle={oracle_proc.stdout[:500]!r}, Agent={agent_proc.stdout[:500]!r}"
        )
        assert oracle_proc.stdout == expected, (
            f"Reference output was incorrect on valid input {index}: "
            f"got={oracle_proc.stdout[:500]!r}, expected={expected[:500]!r}"
        )
        assert agent_proc.stdout == expected, (
            f"Agent output was incorrect on valid input {index}: "
            f"got={agent_proc.stdout[:500]!r}, expected={expected[:500]!r}"
        )


def test_rejects_invalid_headers(rebuilt_oracle):
    invalid_inputs = [
        b"",
        b"D",
        b"DARC",
        b"DARC\x01\x00\x00",
        b"NOPE" + struct.pack("<I", 0),
        b"XXXX" + struct.pack("<I", 4) + b"data",
    ]
    for index, data in enumerate(invalid_inputs):
        oracle_proc = run_program(rebuilt_oracle, data)
        agent_proc = run_program(AGENT_PATH, data)
        assert oracle_proc.returncode == agent_proc.returncode, (
            f"Return code mismatch on invalid input {index}: "
            f"Oracle={oracle_proc.returncode}, Agent={agent_proc.returncode}"
        )
        assert oracle_proc.returncode != 0, (
            f"Reference accepted invalid header {index}"
        )
        assert agent_proc.returncode != 0, (
            f"Agent accepted invalid header {index}"
        )
        assert oracle_proc.stdout == agent_proc.stdout == b"", (
            f"Invalid header {index} produced output"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
