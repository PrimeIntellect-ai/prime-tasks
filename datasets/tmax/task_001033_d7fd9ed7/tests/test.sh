#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import stat
import string
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/legacy_indexer"
AGENT_PATH = "/home/user/indexer"
SOURCE_PATH = "/home/user/indexer.cpp"
NUM_TESTS = 1000


def assert_regular_elf(path):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f"{path} must be a regular file, not a symlink or other file type"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF executable"


def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable at {AGENT_PATH} is not executable"
    assert_regular_elf(AGENT_PATH)

    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "Agent executable must not be a link to the legacy binary"
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), "Agent executable must not be a byte-for-byte copy of the legacy binary"


@pytest.fixture(scope="session")
def rebuilt_agent():
    assert os.path.exists(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    assert not os.path.islink(SOURCE_PATH), f"C++ source at {SOURCE_PATH} must not be a symlink"
    assert stat.S_ISREG(os.lstat(SOURCE_PATH).st_mode), f"C++ source at {SOURCE_PATH} must be a regular file"

    fd, rebuilt_path = tempfile.mkstemp(prefix="indexer_rebuilt_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt_path)

    try:
        proc = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", rebuilt_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert proc.returncode == 0, (
            "Failed to compile /home/user/indexer.cpp:\n"
            + proc.stderr.decode("utf-8", errors="replace")
        )
        assert os.path.isfile(rebuilt_path), "Compilation did not produce an executable"
        assert os.access(rebuilt_path, os.X_OK), "Recompiled source is not executable"
        assert_regular_elf(rebuilt_path)
        yield rebuilt_path
    finally:
        if os.path.exists(rebuilt_path):
            os.unlink(rebuilt_path)


def test_fuzz_equivalence(rebuilt_agent):
    assert os.path.isfile(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle executable at {ORACLE_PATH} is not executable"

    random.seed(42)
    printable_chars = string.printable.replace('\r', '').replace('\n', '')

    for i in range(NUM_TESTS):
        length = random.randint(1, 200)
        input_str = ''.join(random.choice(printable_chars) for _ in range(length))
        input_bytes = (input_str + '\n').encode('utf-8')

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2
        )
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2
        )
        agent_out = agent_proc.stdout

        assert oracle_out == agent_out, (
            f"Mismatch on fuzz input #{i+1}.\n"
            f"Input: {repr(input_str)}\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output: {repr(agent_out)}"
        )

        rebuilt_proc = subprocess.run(
            [rebuilt_agent],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2
        )
        assert rebuilt_proc.returncode == 0, (
            f"Recompiled source failed on fuzz input #{i+1}: "
            f"{rebuilt_proc.stderr!r}"
        )
        assert oracle_out == rebuilt_proc.stdout, (
            f"Recompiled C++ source mismatch on fuzz input #{i+1}.\n"
            f"Input: {repr(input_str)}\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Recompiled output: {repr(rebuilt_proc.stdout)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
