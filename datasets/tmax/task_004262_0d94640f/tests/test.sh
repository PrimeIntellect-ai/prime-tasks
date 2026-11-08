#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest

ORACLE_BIN = "/app/legacy_calc"
AGENT_BIN = "/home/user/solution_bin"
REPO = "/home/user/hash_repo"
SOURCE = os.path.join(REPO, "main.c")
REBUILT_BIN = "/tmp/rebuilt_solution_bin"
N_TESTS = 200


def generate_random_ascii(min_len=5, max_len=500):
    length = random.randint(min_len, max_len)
    chars = string.ascii_letters + string.digits + string.punctuation + ' \n\t'
    return ''.join(random.choice(chars) for _ in range(length)).encode('utf-8')


def run_binary(path, input_data):
    try:
        return subprocess.run(
            [path],
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Binary {path} timed out on input: {input_data!r}")


@pytest.fixture(scope="session", autouse=True)
def rebuild_repository_source():
    assert os.path.isdir(REPO), f"Repository not found at {REPO}"
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"

    proc = subprocess.run(
        ["gcc", "-O2", "-std=c11", SOURCE, "-o", REBUILT_BIN],
        cwd=REPO,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, (
        "The repository source does not compile successfully.\n"
        f"stdout: {proc.stdout!r}\n"
        f"stderr: {proc.stderr!r}"
    )
    assert os.path.isfile(REBUILT_BIN)
    assert os.access(REBUILT_BIN, os.X_OK)


def test_solution_bin_exists():
    assert os.path.exists(AGENT_BIN), f"Solution binary not found at {AGENT_BIN}"
    assert os.path.isfile(AGENT_BIN), f"{AGENT_BIN} is not a file"
    assert os.access(AGENT_BIN, os.X_OK), f"{AGENT_BIN} is not executable"
    with open(AGENT_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{AGENT_BIN} is not a compiled ELF binary"


def test_submission_is_not_legacy_binary_copy():
    with open(ORACLE_BIN, "rb") as f:
        oracle_data = f.read()
    with open(AGENT_BIN, "rb") as f:
        agent_data = f.read()
    assert agent_data != oracle_data, "solution_bin is a byte-for-byte copy of legacy_calc"
    assert not agent_data.startswith(oracle_data), (
        "solution_bin is legacy_calc with data merely appended"
    )


def assert_equivalent(input_data):
    oracle_proc = run_binary(ORACLE_BIN, input_data)
    agent_proc = run_binary(AGENT_BIN, input_data)
    rebuilt_proc = run_binary(REBUILT_BIN, input_data)

    assert oracle_proc.returncode == agent_proc.returncode, (
        f"Return code mismatch on input {input_data!r}. "
        f"Oracle returned {oracle_proc.returncode}, Agent returned {agent_proc.returncode}"
    )
    assert oracle_proc.stdout == agent_proc.stdout, (
        f"Output mismatch on input {input_data!r}.\n"
        f"Oracle output: {oracle_proc.stdout!r}\n"
        f"Agent output: {agent_proc.stdout!r}"
    )

    assert oracle_proc.returncode == rebuilt_proc.returncode, (
        f"Repository source return code mismatch on input {input_data!r}. "
        f"Oracle returned {oracle_proc.returncode}, rebuilt source returned "
        f"{rebuilt_proc.returncode}"
    )
    assert oracle_proc.stdout == rebuilt_proc.stdout, (
        f"Repository source output mismatch on input {input_data!r}.\n"
        f"Oracle output: {oracle_proc.stdout!r}\n"
        f"Rebuilt source output: {rebuilt_proc.stdout!r}"
    )


def test_targeted_equivalence():
    cases = [b"", bytes(range(256)), b"\x00" * 128, b"\xff" * 128]
    for length in range(1, 65):
        cases.append(bytes(((length * 17 + i * 29) & 0xff) for i in range(length)))
    for input_data in cases:
        assert_equivalent(input_data)


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary {ORACLE_BIN} is not executable"

    random.seed(42)
    for _ in range(N_TESTS):
        assert_equivalent(generate_random_ascii())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
