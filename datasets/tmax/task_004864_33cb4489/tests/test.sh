#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

BINARY_PATH = "/home/user/mock_ids"
SOURCE_PATH = "/home/user/mock_ids.c"
IGNORED = ("\\", "'", '"')


def expected_status(payload):
    sanitized = payload.translate({ord(c): None for c in IGNORED})
    return 1 if "eval" in sanitized or "nc" in sanitized else 0


def run_classifier(binary, payload_path):
    result = subprocess.run(
        [binary, str(payload_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    return result.returncode


def test_mock_ids_binary_exists():
    """Ensure the mock_ids binary has been compiled and is executable."""
    assert os.path.exists(BINARY_PATH), f"The binary {BINARY_PATH} does not exist."
    assert os.path.isfile(BINARY_PATH), f"Expected {BINARY_PATH} to be a file."
    assert os.access(BINARY_PATH, os.X_OK), f"The file {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "mock_ids must be a compiled executable"


def test_source_exists_and_compiles():
    """Require the requested C source and verify that gcc can build it."""
    assert os.path.exists(SOURCE_PATH), f"The source {SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"Expected {SOURCE_PATH} to be a file."
    with tempfile.TemporaryDirectory(prefix="ids_build_") as tmp:
        rebuilt = os.path.join(tmp, uuid.uuid4().hex)
        result = subprocess.run(
            ["gcc", SOURCE_PATH, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)


def test_adversarial_corpus():
    """Test the mock_ids binary against the original hidden adversarial corpus."""
    evil_dir = "/app/hidden_eval/evil"
    clean_dir = "/app/hidden_eval/clean"

    evil_bypassed = []
    clean_modified = []
    total_evil = 0
    total_clean = 0

    if os.path.exists(evil_dir):
        for f in os.listdir(evil_dir):
            file_path = os.path.join(evil_dir, f)
            if os.path.isfile(file_path):
                total_evil += 1
                if run_classifier(BINARY_PATH, file_path) != 1:
                    evil_bypassed.append(f)

    if os.path.exists(clean_dir):
        for f in os.listdir(clean_dir):
            file_path = os.path.join(clean_dir, f)
            if os.path.isfile(file_path):
                total_clean += 1
                if run_classifier(BINARY_PATH, file_path) != 0:
                    clean_modified.append(f)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(
            f"{len(evil_bypassed)} of {total_evil} evil bypassed: {', '.join(evil_bypassed)}"
        )
    if clean_modified:
        error_msgs.append(
            f"{len(clean_modified)} of {total_clean} clean modified: {', '.join(clean_modified)}"
        )
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_randomized_payloads_against_derived_oracle():
    """Exercise both the submitted binary and freshly compiled source on opaque paths."""
    rng = secrets.SystemRandom()
    alphabet = string.ascii_letters + string.digits + string.punctuation + " \t\n"

    cases = []

    # Random arbitrary payloads whose answers are computed from the specification.
    for _ in range(50):
        payload = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 400)))
        cases.append(payload)

    # Guarantee many positive cases with freshly randomized obfuscation and context.
    for _ in range(35):
        token = rng.choice(("eval", "nc"))
        hidden = token[0]
        for ch in token[1:]:
            hidden += "".join(rng.choice(IGNORED) for _ in range(rng.randint(1, 5))) + ch
        prefix = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 80)))
        suffix = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 80)))
        cases.append(prefix + hidden + suffix)

    # Guarantee many negative cases, including ignored characters.
    while sum(expected_status(x) == 0 for x in cases) < 35:
        payload = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 300)))
        if expected_status(payload) == 0:
            cases.append(payload)

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="payloads_") as tmp:
        rebuilt = os.path.join(tmp, uuid.uuid4().hex)
        compile_result = subprocess.run(
            ["gcc", SOURCE_PATH, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert compile_result.returncode == 0, compile_result.stderr.decode(errors="replace")

        binaries = (BINARY_PATH, rebuilt)
        for payload in cases:
            payload_path = Path(tmp) / uuid.uuid4().hex
            payload_path.write_text(payload, encoding="utf-8")
            expected = expected_status(payload)
            for binary in binaries:
                actual = run_classifier(binary, payload_path)
                assert actual == expected, (
                    f"Wrong status for randomized payload: expected {expected}, got {actual}"
                )
            payload_path.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
