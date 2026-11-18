#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = "/home/user/wal_sanitizer"
SOURCE_DIR = "/home/user/recovery_src"


def run_case(binary, filepath, expected_code, expected_text):
    try:
        result = subprocess.run(
            [binary, filepath],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{binary} deadlocked or timed out while processing {filepath}")

    assert result.returncode == expected_code, (
        f"{binary} returned {result.returncode} for {filepath}; "
        f"expected {expected_code}. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert expected_text in result.stdout, (
        f"{binary} did not print {expected_text!r} for {filepath}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_wal_sanitizer_exists():
    binary_path = "/home/user/wal_sanitizer"
    assert os.path.isfile(binary_path), f"The sanitizer binary is missing at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"The file at {binary_path} is not executable"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "wal_sanitizer must be a compiled standalone executable"


def test_wal_sanitizer_clean_corpus():
    binary_path = "/home/user/wal_sanitizer"
    clean_dir = "/app/wal_clean/"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No files found in the clean corpus directory."

    failed_files = []

    for filepath in clean_files:
        result = subprocess.run([binary_path, filepath], capture_output=True, text=True)
        if result.returncode != 0 or "VALID" not in result.stdout:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected incorrectly. Offending files: {', '.join(failed_files)}")


def test_wal_sanitizer_evil_corpus():
    binary_path = "/home/user/wal_sanitizer"
    evil_dir = "/app/wal_evil/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No files found in the evil corpus directory."

    failed_files = []

    for filepath in evil_files:
        result = subprocess.run([binary_path, filepath], capture_output=True, text=True)
        if result.returncode != 1 or "CORRUPTED" not in result.stdout:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed validation. Offending files: {', '.join(failed_files)}")


@pytest.fixture(scope="session")
def rebuilt_binary():
    source_path = os.path.join(SOURCE_DIR, "recovery.go")
    module_path = os.path.join(SOURCE_DIR, "go.mod")
    assert os.path.isfile(source_path), f"Missing required source file {source_path}"
    assert os.path.isfile(module_path), f"Missing required module file {module_path}"

    with open(source_path, encoding="utf-8") as f:
        source = f.read()
    assert re.search(
        r'const\s+MAGIC_HEADER(?:\s+\w+)?\s*=\s*"0xDEADBEEF"', source
    ), "recovery.go does not define MAGIC_HEADER as 0xDEADBEEF"

    module_result = subprocess.run(
        ["go", "mod", "edit", "-json"],
        cwd=SOURCE_DIR,
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert module_result.returncode == 0, (
        f"go.mod is invalid: {module_result.stderr or module_result.stdout}"
    )
    module_data = json.loads(module_result.stdout)
    sync_requirements = [
        item for item in module_data.get("Require", [])
        if item.get("Path") == "golang.org/x/sync"
    ]
    assert len(sync_requirements) <= 1, "go.mod still has conflicting golang.org/x/sync requirements"

    output = os.path.join(tempfile.gettempdir(), "rebuilt_wal_sanitizer_" + secrets.token_hex(8))
    build = subprocess.run(
        ["go", "build", "-o", output, "."],
        cwd=SOURCE_DIR,
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert build.returncode == 0, (
        f"The recovery source does not build successfully. stdout={build.stdout!r}, stderr={build.stderr!r}"
    )
    assert os.path.isfile(output) and os.access(output, os.X_OK)

    yield output

    try:
        os.unlink(output)
    except FileNotFoundError:
        pass


def test_source_build_and_unlabeled_generated_inputs(rebuilt_binary):
    token = secrets.token_hex(12)
    record_number = secrets.randbelow(1_000_000) + 100

    cases = [
        (f"0xDEADBEEF valid record {record_number}\n", 0, "VALID"),
        (f"0xDEADBEEF valid record {record_number + 1}\n", 0, "VALID"),
        (f"0xDEADBEEF invalid syntax {token}\n", 1, "CORRUPTED"),
        (f"missing header completely {token}\n", 1, "CORRUPTED"),
        (f"0xDEADBEEF valid ../../../etc/passwd {token}\n", 1, "CORRUPTED"),
        ("0xDEADBEEF\n", 1, "CORRUPTED"),
        (f"0xDEADBEEF corrupted data block {token}\n", 1, "CORRUPTED"),
    ]

    with tempfile.TemporaryDirectory(prefix="wal_inputs_" + token + "_") as temp_dir:
        materialized = []
        for index, (content, code, text) in enumerate(cases):
            filepath = os.path.join(temp_dir, f"chunk_{secrets.token_hex(8)}_{index}.dat")
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(content)
            materialized.append((filepath, code, text))

        for binary in (BINARY_PATH, rebuilt_binary):
            for filepath, code, text in materialized:
                run_case(binary, filepath, code, text)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
