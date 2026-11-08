#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
from pathlib import Path

import pytest

AGENT_BIN = Path("/home/user/fixed_parser")
ORACLE_BIN = Path("/app/oracle_parser")
REPO = Path("/home/user/telemetry_repo")
SOURCE = REPO / "telemetry.c"
MAKEFILE = REPO / "Makefile"


def run_binary(path, argument, timeout=2):
    try:
        return subprocess.run(
            [str(path), argument],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out on input of length {len(argument)}")
    except Exception as exc:
        pytest.fail(f"Failed to run {path}: {exc}")


def strip_c_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def test_fixed_parser_exists_and_executable():
    assert AGENT_BIN.exists(), f"Expected file {AGENT_BIN} does not exist. Did you compile your fixed C program?"
    assert AGENT_BIN.is_file(), f"Expected {AGENT_BIN} to be a file."
    assert not AGENT_BIN.is_symlink(), f"Expected {AGENT_BIN} to be a compiled file, not a symlink."
    assert os.access(AGENT_BIN, os.X_OK), f"Expected {AGENT_BIN} to be executable."
    assert AGENT_BIN.read_bytes()[:4] == b"\x7fELF", f"Expected {AGENT_BIN} to be a compiled ELF executable."


def test_oracle_parser_exists():
    assert ORACLE_BIN.exists(), f"Reference oracle {ORACLE_BIN} is missing."
    assert ORACLE_BIN.is_file(), f"Reference oracle {ORACLE_BIN} is not a file."
    assert os.access(ORACLE_BIN, os.X_OK), f"Reference oracle {ORACLE_BIN} is not executable."


def test_submission_is_not_copied_oracle():
    assert AGENT_BIN.read_bytes() != ORACLE_BIN.read_bytes(), (
        "fixed_parser is byte-identical to the shipped reference oracle; "
        "the repaired program must be built from the repository fix."
    )


def test_repository_contains_requested_repairs():
    assert SOURCE.is_file(), f"Missing source file {SOURCE}"
    assert MAKEFILE.is_file(), f"Missing build file {MAKEFILE}"

    code = strip_c_comments(SOURCE.read_text())
    makefile = MAKEFILE.read_text()

    assert re.search(r"\b0x1A4F\b", code, flags=re.I), (
        "telemetry.c does not contain the FATAL_OFFSET recovered from the bug report."
    )

    worker = re.search(
        r"\bthread_worker\s*\([^)]*\)\s*\{(?P<body>.*?)\breturn\s+NULL\s*;",
        code,
        flags=re.S,
    )
    assert worker, "Could not find the thread_worker implementation."
    body = worker.group("body")
    lock = body.find("pthread_mutex_lock")
    copy = min([p for p in (body.find("strncpy"), body.find("strcpy"), body.find("memcpy")) if p >= 0], default=-1)
    unlock = body.find("pthread_mutex_unlock")
    assert lock >= 0, "thread_worker is missing pthread_mutex_lock."
    assert copy >= 0, "thread_worker no longer performs the string extraction copy."
    assert unlock >= 0, "thread_worker is missing pthread_mutex_unlock."
    assert lock < copy < unlock, "The extraction buffer copy must be enclosed by the mutex lock and unlock."

    assert re.search(r"\bgcc\b", makefile), "The Makefile must compile the C program with gcc."
    assert re.search(r"(?:-pthread\b|-lpthread\b)", makefile), (
        "The Makefile does not link pthread support."
    )


def test_repaired_makefile_builds_source():
    built = REPO / "telemetry"
    if built.exists() or built.is_symlink():
        built.unlink()
    proc = subprocess.run(
        ["make", "-B"], cwd=REPO, capture_output=True, text=True, timeout=20
    )
    assert proc.returncode == 0, f"The repaired Makefile failed:\n{proc.stdout}\n{proc.stderr}"
    assert built.is_file() and os.access(built, os.X_OK), "Makefile did not produce an executable telemetry binary."
    assert built.read_bytes()[:4] == b"\x7fELF", "Makefile output is not a compiled ELF executable."

    probe = "makefile-build-probe"
    result = run_binary(built, probe)
    assert result.returncode == 0
    assert result.stdout == probe + "\n"


def test_derived_boundary_behavior():
    # The implementation's 1024-byte extraction buffer safely preserves at most
    # 1023 input bytes and then emits exactly one newline.
    cases = [
        "",
        "x",
        "A" * 9,
        "B" * 1022,
        "C" * 1023,
        "D" * 1024,
        "E" * 2048,
        "0123456789" * 500,
    ]
    for value in cases:
        proc = run_binary(AGENT_BIN, value)
        assert proc.returncode == 0, f"fixed_parser exited with {proc.returncode} for length {len(value)}"
        expected = value[:1023] + "\n"
        assert proc.stdout == expected, (
            f"Incorrect extraction for input length {len(value)}: "
            f"expected {expected!r}, got {proc.stdout!r}"
        )


def test_fuzz_equivalence():
    if not AGENT_BIN.exists() or not os.access(AGENT_BIN, os.X_OK):
        pytest.fail(f"Cannot run fuzzing: {AGENT_BIN} is missing or not executable.")
    if not ORACLE_BIN.exists() or not os.access(ORACLE_BIN, os.X_OK):
        pytest.fail(f"Cannot run fuzzing: {ORACLE_BIN} is missing or not executable.")

    random.seed(42)
    charset = string.ascii_letters + string.digits + string.punctuation + " "
    for _ in range(5000):
        length = random.randint(10, 256)
        test_input = "".join(random.choices(charset, k=length))
        oracle_proc = run_binary(ORACLE_BIN, test_input)
        agent_proc = run_binary(AGENT_BIN, test_input)
        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on input: {test_input!r}\n"
            f"Expected (Oracle): {oracle_proc.stdout!r}\n"
            f"Got (Agent): {agent_proc.stdout!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
