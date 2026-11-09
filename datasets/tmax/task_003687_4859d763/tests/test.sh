#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

EXECUTABLE = "/home/user/sanitize_query"
SOURCE = "/home/user/sanitizer.c"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
REBUILT = "/tmp/sanitize_query_rebuilt"


def run_sanitizer(executable, path):
    try:
        return subprocess.run(
            [executable, str(path)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=4,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitizer timed out on {path}")


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}. Did you compile your C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sanitize_query must be a compiled executable"


def test_source_exists_and_builds():
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    result = subprocess.run(
        ["gcc", SOURCE, "/opt/cJSON/cJSON.c", "-I/opt/cJSON", "-o", REBUILT, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, "sanitizer.c does not compile with cJSON:\n" + result.stderr.decode(errors="replace")


def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus directory missing: {CLEAN_CORPUS}"
    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.json')]
    assert len(clean_files) > 0, f"No JSON files found in {CLEAN_CORPUS}"

    failed_files = []
    for f in clean_files:
        file_path = os.path.join(CLEAN_CORPUS, f)
        if run_sanitizer(EXECUTABLE, file_path) != 0:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (rejected). Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus directory missing: {EVIL_CORPUS}"
    evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith('.json')]
    assert len(evil_files) > 0, f"No JSON files found in {EVIL_CORPUS}"

    bypassed_files = []
    for f in evil_files:
        file_path = os.path.join(EVIL_CORPUS, f)
        if run_sanitizer(EXECUTABLE, file_path) == 0:
            bypassed_files.append(f)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed (accepted). Offending files: {', '.join(bypassed_files)}")


def write_json(path, value):
    path.write_text(json.dumps(value, separators=(",", ":")), encoding="utf-8")


def test_generated_queries_are_parsed_and_validated(test_source_exists_and_builds):
    token = secrets.token_hex(8)
    parameter = "$param_" + secrets.token_hex(6)

    clean_cases = [
        {"$match": {"type": "Dataset", "status": parameter}, "$project": {"confidence_score": 1}},
        {"$match": {"type": "Experiment", "id": parameter, "owner": "$owner_" + token}, "$project": {"confidence_score": 1, "data": 1}},
    ]
    evil_cases = [
        {"$match": {"type": "Admin", "status": parameter}, "$project": {"confidence_score": 1}},
        {"$match": {"type": "Billing", "id": parameter}, "$project": {"confidence_score": 1}},
        {"$match": {"type": "Other", "id": parameter}, "$project": {"confidence_score": 1}},
        {"$match": {"type": "Dataset", "status": "active_" + token}, "$project": {"confidence_score": 1}},
        {"$match": {"type": "Experiment", "status": 7}, "$project": {"confidence_score": 1}},
        {"$match": {"type": "Dataset", "status": parameter}, "$project": {"data": 1}},
        {"$match": {"type": "Experiment", "status": parameter}},
    ]

    with tempfile.TemporaryDirectory(prefix="query_checks_") as root:
        root = Path(root)
        # Deliberately invert suggestive directory names so path-based classifiers fail.
        clean_dir = root / ("evil_" + secrets.token_hex(5))
        evil_dir = root / ("clean_" + secrets.token_hex(5))
        clean_dir.mkdir()
        evil_dir.mkdir()

        generated = []
        for expected_clean, cases, directory in (
            (True, clean_cases, clean_dir),
            (False, evil_cases, evil_dir),
        ):
            for payload in cases:
                path = directory / (secrets.token_hex(12) + ".json")
                write_json(path, payload)
                generated.append((path, expected_clean))

        malformed = evil_dir / (secrets.token_hex(12) + ".json")
        malformed.write_text('{"$match": {"type": "Dataset",', encoding="utf-8")
        generated.append((malformed, False))

        for executable in (EXECUTABLE, REBUILT):
            for path, expected_clean in generated:
                accepted = run_sanitizer(executable, path) == 0
                assert accepted == expected_clean, (
                    f"{executable} {'accepted' if accepted else 'rejected'} an "
                    f"unexpected generated query: {path.read_text(errors='replace')}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
