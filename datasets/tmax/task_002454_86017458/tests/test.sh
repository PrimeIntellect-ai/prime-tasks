#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

import pytest

AGENT_SOURCE = "/home/user/bio_scorer.c"
AGENT_BINARY = "/home/user/bio_scorer"


def expected_score(sequence):
    weights = {"A": 13, "C": 27, "G": 31, "T": 42}
    score = 0
    for index, nucleotide in enumerate(sequence, start=1):
        score += index * weights[nucleotide]
        score %= 10009
    return score


@pytest.fixture(scope="session")
def compiled_source():
    assert os.path.isfile(AGENT_SOURCE), f"Expected C source is missing: {AGENT_SOURCE}"
    assert os.path.getsize(AGENT_SOURCE) > 0, f"Expected C source is empty: {AGENT_SOURCE}"

    fd, output_path = tempfile.mkstemp(prefix="compiled_bio_scorer_", dir="/tmp")
    os.close(fd)
    os.unlink(output_path)

    proc = subprocess.run(
        ["gcc", "-O2", "-std=c11", AGENT_SOURCE, "-o", output_path],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, (
        f"Could not compile {AGENT_SOURCE}.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.isfile(output_path)
    assert os.access(output_path, os.X_OK)

    yield output_path

    try:
        os.unlink(output_path)
    except FileNotFoundError:
        pass


def test_bio_scorer_exists_and_executable():
    assert os.path.isfile(AGENT_BINARY), f"Expected agent binary is missing: {AGENT_BINARY}"
    assert os.access(AGENT_BINARY, os.X_OK), f"Agent binary is not executable: {AGENT_BINARY}"
    with open(AGENT_BINARY, "rb") as binary_file:
        assert binary_file.read(4) == b"\x7fELF", "bio_scorer must be a compiled executable"


def test_source_exists_and_compiles(compiled_source):
    assert os.path.isfile(compiled_source)


@pytest.mark.parametrize("program_fixture", ["agent", "source"])
def test_exactly_one_argument(program_fixture, compiled_source):
    program = AGENT_BINARY if program_fixture == "agent" else compiled_source

    no_arg = subprocess.run([program], capture_output=True, text=True, timeout=5)
    assert no_arg.returncode != 0, f"{program} must reject invocation without a sequence"

    extra_arg = subprocess.run([program, "A", "C"], capture_output=True, text=True, timeout=5)
    assert extra_arg.returncode != 0, f"{program} must reject invocation with extra arguments"


def test_fuzz_equivalence(compiled_source):
    random.seed(42)
    nucleotides = ["A", "C", "G", "T"]

    for iteration in range(1000):
        length = random.randint(1, 1024)
        dna_sequence = "".join(random.choices(nucleotides, k=length))
        expected = str(expected_score(dna_sequence))

        for program in (AGENT_BINARY, compiled_source):
            proc = subprocess.run(
                [program, dna_sequence],
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert proc.returncode == 0, (
                f"{program} failed with exit code {proc.returncode} on iteration {iteration + 1}"
            )
            assert proc.stdout.strip() == expected, (
                f"Output mismatch for {program} on iteration {iteration + 1}.\n"
                f"Input length: {length}\n"
                f"Input sequence: {dna_sequence}\n"
                f"Expected output: '{expected}'\n"
                f"Actual output: '{proc.stdout.strip()}'"
            )
            assert proc.stdout == expected + "\n", (
                f"{program} must output exactly the score followed by one newline"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
