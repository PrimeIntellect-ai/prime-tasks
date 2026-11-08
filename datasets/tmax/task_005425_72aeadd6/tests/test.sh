#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile
from collections import Counter

import pytest

BINARY_PATH = "/home/user/log_sanitizer/sanitizer"
PROJECT_DIR = "/home/user/log_sanitizer"
CLEAN_CORPUS_DIR = "/home/user/log_sanitizer/corpus/clean"
EVIL_CORPUS_DIR = "/home/user/log_sanitizer/corpus/evil"
TIMEOUT = 2.0


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"File at {BINARY_PATH} is not executable"


def test_project_rebuilds_compiled_binary():
    source = os.path.join(PROJECT_DIR, "sanitizer.c")
    makefile = os.path.join(PROJECT_DIR, "Makefile")
    assert os.path.isfile(source), f"Source file missing: {source}"
    assert os.path.isfile(makefile), f"Makefile missing: {makefile}"

    os.unlink(BINARY_PATH)
    result = subprocess.run(
        ["make", "-B", "sanitizer"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Project failed to rebuild with make:\n{result.stdout}\n{result.stderr}"
    )
    assert os.path.isfile(BINARY_PATH), "make did not recreate the sanitizer binary"
    assert os.access(BINARY_PATH, os.X_OK), "Rebuilt sanitizer is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sanitizer is not a compiled ELF binary"


def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory."

    failed_files = []
    for filepath in clean_files:
        try:
            result = subprocess.run([BINARY_PATH, filepath], capture_output=True, timeout=TIMEOUT)
            if result.returncode != 0:
                failed_files.append(os.path.basename(filepath))
        except subprocess.TimeoutExpired:
            failed_files.append(f"{os.path.basename(filepath)} (timeout)")
        except Exception as e:
            failed_files.append(f"{os.path.basename(filepath)} (error: {e})")

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean logs modified/rejected: {', '.join(failed_files)}")


def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus directory."

    failed_files = []
    for filepath in evil_files:
        try:
            result = subprocess.run([BINARY_PATH, filepath], capture_output=True, timeout=TIMEOUT)
            if result.returncode != 1:
                failed_files.append(os.path.basename(filepath))
        except subprocess.TimeoutExpired:
            failed_files.append(f"{os.path.basename(filepath)} (timeout)")
        except Exception as e:
            failed_files.append(f"{os.path.basename(filepath)} (error: {e})")

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil logs bypassed/accepted: {', '.join(failed_files)}")


def expected_status(data):
    if data:
        counts = Counter(data)
        entropy = -sum((n / len(data)) * math.log2(n / len(data)) for n in counts.values())
        if entropy > 7.5:
            return 1

    depth = 0
    for value in data:
        if depth > 50:
            return 1
        if value == ord('['):
            depth += 1
        elif value == ord(']'):
            if depth == 0:
                return 1
            depth -= 1
        # A backslash must advance like every other character; it must not recurse
        # forever or prevent the following bracket from being parsed.
    if depth > 50:
        return 1
    return 0 if depth == 0 else 1


def test_generated_hidden_cases_at_same_path():
    cases = [
        b"",
        b"plain informational message\n",
        b"[]",
        b"[outer [inner] tail]",
        b"[a][b[c]d]",
        b"]",
        b"[",
        b"[[[]]",
        b"[]]",
        b"\\",
        b"\\[",
        b"\\]",
        b"[info] \\\n",
        b"\\[\\[\\[ malicious\n",
        b"[" * 50 + b"]" * 50,
        b"[" * 51 + b"]" * 51,
        bytes(range(1, 256)) * 4,
    ]

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = b"abcXYZ 0123[]\\_-:"
    for _ in range(80):
        cases.append(bytes(rng.choice(alphabet) for _ in range(rng.randrange(0, 181))))

    with tempfile.TemporaryDirectory(prefix="sanitizer_eval_") as directory:
        # Every input is written to the exact same unpredictable path, so decisions
        # cannot be based on clean/evil directory or filename labels.
        path = os.path.join(directory, "input.log")
        for index, data in enumerate(cases):
            with open(path, "wb") as f:
                f.write(data)
            expected = expected_status(data)
            try:
                result = subprocess.run(
                    [BINARY_PATH, path], capture_output=True, timeout=TIMEOUT
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Generated case {index} timed out: {data[:100]!r}")
            assert result.returncode == expected, (
                f"Generated case {index} returned {result.returncode}, expected "
                f"{expected}: {data[:100]!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
