#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

EXECUTABLE_PATH = "/home/user/trace_filter"
SOURCE_PATH = "/home/user/trace_filter.cpp"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def test_executable_exists_and_is_file():
    assert os.path.exists(EXECUTABLE_PATH), f"Executable {EXECUTABLE_PATH} does not exist."
    assert os.path.isfile(EXECUTABLE_PATH), f"{EXECUTABLE_PATH} is not a file."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable."


def test_clean_corpus_accepted():
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]
    assert len(clean_files) > 0, f"No CSV files found in {CLEAN_CORPUS_DIR}."

    rejected_files = []
    for f in clean_files:
        result = subprocess.run([EXECUTABLE_PATH, f], capture_output=True)
        if result.returncode != 0:
            rejected_files.append(os.path.basename(f))

    if rejected_files:
        pytest.fail(f"{len(rejected_files)} of {len(clean_files)} clean rejected: {', '.join(rejected_files)}")


def test_evil_corpus_rejected():
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]
    assert len(evil_files) > 0, f"No CSV files found in {EVIL_CORPUS_DIR}."

    bypassed_files = []
    for f in evil_files:
        result = subprocess.run([EXECUTABLE_PATH, f], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(f))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}")


@pytest.fixture(scope="module")
def rebuilt_executable(tmp_path_factory):
    assert os.path.exists(SOURCE_PATH), f"C++ source {SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file."

    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not a compiled ELF executable."

    build_dir = tmp_path_factory.mktemp("cpp_build")
    rebuilt = build_dir / "trace_filter_rebuilt"
    result = subprocess.run(
        ["g++", SOURCE_PATH, "-O2", "-o", str(rebuilt)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Failed to compile {SOURCE_PATH} as C++:\n{result.stderr}"
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)
    return str(rebuilt)


def test_cpp_source_exists_and_compiles(rebuilt_executable):
    assert os.path.isfile(rebuilt_executable)


def make_rows(rng, row_count):
    rows = []
    for timestamp in range(row_count):
        instructions = rng.randint(1, 100000)
        cycles = instructions + rng.randint(0, 50000)
        l1_misses = rng.randint(0, 10000)
        l2_misses = rng.randint(0, 10000)
        rows.append([timestamp, instructions, cycles, l1_misses, l2_misses])
    return rows


def test_generated_content_at_neutral_paths(rebuilt_executable):
    rng = random.SystemRandom()
    cases = []

    for _ in range(12):
        rows = make_rows(rng, rng.randint(1, 8))
        cases.append((rows, 0))

    for _ in range(9):
        rows = make_rows(rng, rng.randint(1, 8))
        index = rng.randrange(len(rows))
        rows[index][4] = -rng.randint(1, 10000)
        cases.append((rows, 1))

    for _ in range(9):
        rows = make_rows(rng, rng.randint(1, 8))
        index = rng.randrange(len(rows))
        rows[index][2] = rows[index][1] - rng.randint(1, rows[index][1])
        cases.append((rows, 1))

    for _ in range(6):
        rows = make_rows(rng, rng.randint(1, 8))
        first = rng.randrange(len(rows))
        second = rng.randrange(len(rows))
        rows[first][4] = -rng.randint(1, 10000)
        rows[second][2] = rows[second][1] - rng.randint(1, rows[second][1])
        cases.append((rows, 1))

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="trace_cases_") as case_dir:
        generated = []
        for rows, expected in cases:
            path = Path(case_dir) / f"{secrets.token_hex(12)}.csv"
            with path.open("w", newline="") as f:
                f.write("timestamp,instructions,cycles,l1_misses,l2_misses\n")
                for row in rows:
                    f.write(",".join(map(str, row)) + "\n")
            generated.append((str(path), expected))

        for program in (EXECUTABLE_PATH, rebuilt_executable):
            failures = []
            for path, expected in generated:
                result = subprocess.run([program, path], capture_output=True, timeout=5)
                if result.returncode != expected:
                    failures.append(
                        f"{os.path.basename(path)} expected {expected}, got {result.returncode}"
                    )
            assert not failures, f"Generated trace failures for {program}: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
