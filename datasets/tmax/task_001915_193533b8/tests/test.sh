#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import subprocess
import tempfile
import pytest

ENTRY_POINT = "/home/user/audit_filter.sh"
CLEAN_CORPUS = "/app/eval_corpus/clean"
EVIL_CORPUS = "/app/eval_corpus/evil"
SALT = "Omega99X"


def run_filter(filepath):
    try:
        return subprocess.run(
            [ENTRY_POINT, filepath], capture_output=True, timeout=120
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Audit filter timed out for {filepath}")


def test_script_exists_and_executable():
    assert os.path.isfile(ENTRY_POINT), f"The script {ENTRY_POINT} does not exist."
    assert os.access(ENTRY_POINT, os.X_OK), f"The script {ENTRY_POINT} is not executable."


def test_clean_corpus_preserved():
    """Ensure the script exits with 0 for all legitimate tokens."""
    if not os.path.isdir(CLEAN_CORPUS):
        pytest.fail(f"Clean corpus directory missing: {CLEAN_CORPUS}")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    if not clean_files:
        pytest.fail(f"No files found in clean corpus directory: {CLEAN_CORPUS}")

    failed_files = []
    total = len(clean_files)

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS, filename)
        result = run_filter(filepath)
        if result.returncode != 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {total} clean modified/rejected (expected exit 0). Offending files: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    """Ensure the script exits with 1 for all forged tokens."""
    if not os.path.isdir(EVIL_CORPUS):
        pytest.fail(f"Evil corpus directory missing: {EVIL_CORPUS}")

    evil_files = [f for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    if not evil_files:
        pytest.fail(f"No files found in evil corpus directory: {EVIL_CORPUS}")

    failed_files = []
    total = len(evil_files)

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS, filename)
        result = run_filter(filepath)
        if result.returncode != 1:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {total} evil bypassed (expected exit 1). Offending files: {', '.join(failed_files)}")


def test_runtime_generated_tokens_in_neutral_paths():
    """Exercise fresh valid and forged tokens without clean/evil path labels."""
    rng = secrets.SystemRandom()
    cases = []

    for _ in range(4):
        username = "u" + secrets.token_hex(6)
        pin = rng.randrange(0, 501)
        valid_token = hashlib.sha256(
            f"{SALT}{username}{pin:04d}".encode()
        ).hexdigest()
        cases.append((username, valid_token, 0))

        valid_hashes = {
            hashlib.sha256(f"{SALT}{username}{candidate:04d}".encode()).hexdigest()
            for candidate in range(10000)
        }
        forged_token = secrets.token_hex(32)
        while forged_token in valid_hashes:
            forged_token = secrets.token_hex(32)
        cases.append((username, forged_token, 1))

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="audit_inputs_") as directory:
        generated = []
        for username, token, expected in cases:
            path = os.path.join(directory, secrets.token_hex(8) + ".log")
            with open(path, "w", encoding="ascii") as handle:
                handle.write(f"{username}:{token}\n")
            generated.append((path, expected))

        rng.shuffle(generated)
        failures = []
        for path, expected in generated:
            result = run_filter(path)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)} expected {expected}, got {result.returncode}"
                )

        assert not failures, "Runtime-generated token failures: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
