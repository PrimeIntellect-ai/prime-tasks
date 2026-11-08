#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import hashlib
import os
import random
import stat
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/oracle_prng"
AGENT_PATH = "/home/user/fixed_prng"
SOURCE_PATH = "/home/user/prng_project/main.cpp"
NUM_TESTS = 100
MASK = (1 << 64) - 1
MULTIPLIER = 6364136223846793005
ADDEND = 1442695040888963407


def expected(seed, iterations):
    state = seed
    for _ in range(iterations):
        state = ((state * MULTIPLIER + ADDEND) & MASK) ^ (state >> 27)
    return str(state)


def run_program(path, seed, iterations):
    try:
        result = subprocess.run(
            [path, str(seed), str(iterations)],
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Program {path} failed on input '{seed} {iterations}': {exc.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Program {path} timed out on input '{seed} {iterations}'")
    return result.stdout.strip()


def file_digest(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.digest()


@contextlib.contextmanager
def temporarily_hide(paths):
    moved = []
    try:
        for path in paths:
            if os.path.lexists(path):
                hidden = f"{path}.verifier-hidden-{os.getpid()}-{len(moved)}"
                os.rename(path, hidden)
                moved.append((path, hidden))
        yield
    finally:
        for path, hidden in reversed(moved):
            if os.path.lexists(hidden):
                os.rename(hidden, path)


@pytest.fixture(scope="session")
def rebuilt_prng():
    assert os.path.isfile(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    fd, output_path = tempfile.mkstemp(prefix="rebuilt_prng_", dir="/tmp")
    os.close(fd)
    os.unlink(output_path)
    result = subprocess.run(
        ["g++", "-O3", "-std=c++11", SOURCE_PATH, "-o", output_path],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Corrected main.cpp does not compile: {result.stderr}"
    yield output_path
    if os.path.exists(output_path):
        os.unlink(output_path)


def test_fixed_prng_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert stat.S_ISREG(os.lstat(AGENT_PATH).st_mode), "Agent executable must be a regular file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable at {AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Agent executable must be a compiled ELF binary"


def test_submission_is_not_oracle_copy():
    assert os.path.isfile(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle executable at {ORACLE_PATH} is not executable"
    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "fixed_prng must not be the oracle itself"
    assert file_digest(AGENT_PATH) != file_digest(ORACLE_PATH), "fixed_prng is a byte-identical copy of the oracle"


def test_corrected_source_build_is_independently_functional(rebuilt_prng):
    cases = [
        (0, 0), (0, 1), (1, 1), (MASK, 1), (MASK, 2),
        (2**63, 3), (123456789, 10), (9876543210123456789, 257),
    ]
    rng = random.Random(20240517)
    cases.extend((rng.randrange(1 << 64), rng.randint(0, 1500)) for _ in range(40))

    # A corrected source build must work without delegating to either supplied binary.
    with temporarily_hide([ORACLE_PATH, AGENT_PATH]):
        for seed, iterations in cases:
            assert run_program(rebuilt_prng, seed, iterations) == expected(seed, iterations), (
                f"main.cpp build has incorrect output for '{seed} {iterations}'"
            )


def test_fixed_binary_matches_derived_recurrence_without_oracle():
    rng = random.Random(99173)
    cases = [(0, 0), (0, 1), (1, 1), (MASK, 1), (MASK, 100)]
    cases.extend((rng.randrange(1 << 64), rng.randint(0, 2000)) for _ in range(35))

    # Prevent an executable wrapper from passing by invoking /app/oracle_prng.
    with temporarily_hide([ORACLE_PATH]):
        for seed, iterations in cases:
            assert run_program(AGENT_PATH, seed, iterations) == expected(seed, iterations), (
                f"fixed_prng has incorrect output for '{seed} {iterations}'"
            )


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle executable at {ORACLE_PATH} is not executable"

    random.seed(42)
    for _ in range(NUM_TESTS):
        seed = random.randint(0, (1 << 64) - 1)
        iterations = random.randint(100, 10000)
        oracle_output = run_program(ORACLE_PATH, seed, iterations)
        agent_output = run_program(AGENT_PATH, seed, iterations)
        assert agent_output == oracle_output, (
            f"Mismatch on input '{seed} {iterations}'. "
            f"Oracle output: '{oracle_output}', Agent output: '{agent_output}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
