#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import random
import pytest

EXECUTABLE_PATH = "/home/user/dataset_filter/target/release/dataset_filter"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"


def run_filter(path):
    try:
        return subprocess.run(
            [EXECUTABLE_PATH, str(path)],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"dataset_filter hung while checking {path}")


def test_executable_exists():
    assert os.path.exists(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}"
    assert os.path.isfile(EXECUTABLE_PATH), f"Path is not a file: {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File is not executable: {EXECUTABLE_PATH}"


def test_clean_corpus():
    if not os.path.exists(EXECUTABLE_PATH):
        pytest.skip("Executable not found")

    clean_dirs = [os.path.join(CLEAN_CORPUS, d) for d in os.listdir(CLEAN_CORPUS) if os.path.isdir(os.path.join(CLEAN_CORPUS, d))]
    assert len(clean_dirs) > 0, f"No clean directories found in {CLEAN_CORPUS}"

    failed_clean = []
    for clean_dir in clean_dirs:
        result = subprocess.run([EXECUTABLE_PATH, clean_dir], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(clean_dir))

    if failed_clean:
        pytest.fail(f"{len(failed_clean)} of {len(clean_dirs)} clean directories modified/rejected. Offending: {', '.join(failed_clean)}")


def test_evil_corpus():
    if not os.path.exists(EXECUTABLE_PATH):
        pytest.skip("Executable not found")

    evil_dirs = [os.path.join(EVIL_CORPUS, d) for d in os.listdir(EVIL_CORPUS) if os.path.isdir(os.path.join(EVIL_CORPUS, d))]
    assert len(evil_dirs) > 0, f"No evil directories found in {EVIL_CORPUS}"

    failed_evil = []
    for evil_dir in evil_dirs:
        result = subprocess.run([EXECUTABLE_PATH, evil_dir], capture_output=True)
        if result.returncode != 1:
            failed_evil.append(os.path.basename(evil_dir))

    if failed_evil:
        pytest.fail(f"{len(failed_evil)} of {len(evil_dirs)} evil directories bypassed. Offending: {', '.join(failed_evil)}")


def test_generated_unlabelled_cases(tmp_path):
    assert os.path.exists(EXECUTABLE_PATH)
    base = tmp_path / secrets.token_hex(12)
    base.mkdir()
    cases = []

    def new_case(expected):
        path = base / secrets.token_hex(12)
        path.mkdir()
        cases.append((path, expected))
        return path

    # Clean ordinary and nested data.
    case = new_case(0)
    (case / "nested").mkdir()
    (case / "nested" / "sample.dat").write_bytes(b"ordinary data")
    (case / "notes.txt").write_bytes(b"DEADBEEF")

    # The magic bytes are only corrupt at offset zero of a lowercase .dat file.
    case = new_case(0)
    (case / "magic.txt").write_bytes(b"\xde\xad\xbe\xefpayload")
    (case / "upper.DAT").write_bytes(b"\xde\xad\xbe\xefpayload")
    (case / "offset.dat").write_bytes(b"X\xde\xad\xbe\xefpayload")
    (case / "short.dat").write_bytes(b"\xde\xad\xbe")

    # A normal symlink must not be confused with a loop.
    case = new_case(0)
    (case / "target.dat").write_bytes(b"clean")
    os.symlink("target.dat", case / "alias.dat")

    # Corrupted files at different, randomly named depths.
    case = new_case(1)
    (case / (secrets.token_hex(6) + ".dat")).write_bytes(b"\xde\xad\xbe\xef" + os.urandom(11))

    case = new_case(1)
    deep = case / secrets.token_hex(6) / secrets.token_hex(6)
    deep.mkdir(parents=True)
    (deep / (secrets.token_hex(6) + ".dat")).write_bytes(b"\xde\xad\xbe\xef")
    (case / "clean.dat").write_bytes(b"not corrupt")

    # Three distinct cyclic symlink structures.
    case = new_case(1)
    os.symlink("self", case / "self")

    case = new_case(1)
    os.symlink("second", case / "first")
    os.symlink("first", case / "second")

    case = new_case(1)
    child = case / secrets.token_hex(6)
    child.mkdir()
    os.symlink("..", child / "up")

    random.SystemRandom().shuffle(cases)
    failures = []
    for path, expected in cases:
        actual = run_filter(path)
        if actual != expected:
            failures.append(f"{path.name}: expected {expected}, got {actual}")

    assert not failures, "Generated behavioral cases failed: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
