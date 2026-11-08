#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = "/app/validator/target/debug/validator"
VALIDATOR_DIR = "/app/validator"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def run_validator(path):
    return subprocess.run(
        [BINARY_PATH, path],
        capture_output=True,
        timeout=10,
    )


def assert_graceful_rejection(result, description):
    stderr = result.stderr.decode("utf-8", errors="replace").lower()
    assert result.returncode > 0, f"Malformed payload was accepted: {description}"
    assert result.returncode != 101, f"Validator panicked on malformed payload: {description}"
    assert "panicked at" not in stderr and "stack backtrace" not in stderr, \
        f"Validator emitted a Rust panic on malformed payload: {description}"


def test_project_builds_and_keeps_serde_update():
    result = subprocess.run(
        ["cargo", "build"],
        cwd=VALIDATOR_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"cargo build failed:\n{result.stdout}\n{result.stderr}"

    metadata = subprocess.run(
        ["cargo", "metadata", "--format-version", "1"],
        cwd=VALIDATOR_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert metadata.returncode == 0, f"cargo metadata failed: {metadata.stderr}"
    packages = json.loads(metadata.stdout)["packages"]
    serde_versions = [p["version"] for p in packages if p["name"] == "serde"]
    assert serde_versions, "The serde dependency was removed instead of resolving the conflict."
    assert any(tuple(int(x) for x in v.split(".")[:3]) >= (1, 0, 130) for v in serde_versions), \
        f"The core serde update was downgraded: {serde_versions}"


def test_binary_exists():
    """Verify that the validator binary has been built."""
    assert os.path.isfile(BINARY_PATH), f"Validator binary not found at {BINARY_PATH}. Did the build fail?"
    assert os.access(BINARY_PATH, os.X_OK), f"Validator binary at {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Validator is not a compiled Linux executable."


def test_adversarial_corpus():
    """Verify that the validator correctly processes clean and evil corpora."""
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    assert len(clean_files) > 0, "Clean corpus is empty."
    assert len(evil_files) > 0, "Evil corpus is empty."

    clean_failures = []
    for clean_file in clean_files:
        result = run_validator(clean_file)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(clean_file))

    evil_failures = []
    panic_failures = []
    for evil_file in evil_files:
        result = run_validator(evil_file)
        if result.returncode == 0:
            evil_failures.append(os.path.basename(evil_file))
        stderr = result.stderr.decode("utf-8", errors="replace").lower()
        if result.returncode < 0 or result.returncode == 101 or "panicked at" in stderr or "stack backtrace" in stderr:
            panic_failures.append(os.path.basename(evil_file))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")
    if panic_failures:
        error_messages.append(f"{len(panic_failures)} evil payloads caused a panic/crash: {', '.join(panic_failures)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_generated_payloads_on_neutral_random_paths():
    """Exercise content-derived cases whose paths do not reveal expected outcomes."""
    rng = random.SystemRandom()
    cases = []

    # Well-formed payloads consist of arbitrary bytes followed by the 0xFF terminator.
    for length in [0, 1, 2, 17, 257, 4096]:
        prefix = bytes(rng.randrange(0, 255) for _ in range(length))
        cases.append((prefix + b"\xff", True, f"terminated payload of length {length + 1}"))

    # Empty and unterminated payloads are malformed, including a large input that
    # must be rejected without an out-of-bounds panic or uncontrolled allocation.
    cases.append((b"", False, "empty payload"))
    for length in [1, 2, 3, 31, 1024, 1024 * 1024]:
        data = bytes(rng.randrange(0, 255) for _ in range(length))
        cases.append((data, False, f"unterminated payload of length {length}"))

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="validator-cases-") as directory:
        for data, should_accept, description in cases:
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, "wb") as f:
                f.write(data)
            result = run_validator(path)
            if should_accept:
                assert result.returncode == 0, \
                    f"Valid {description} was rejected (exit {result.returncode}): {result.stderr!r}"
            else:
                assert_graceful_rejection(result, description)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
