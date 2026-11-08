#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import time
import uuid

import jwt
import pytest

CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
PROJECT_DIR = "/app/auditor-tool"
BUILD_DIR = os.path.join(PROJECT_DIR, "build")
EXECUTABLE = os.path.join(BUILD_DIR, "validator")
SECRET = "ssh-audit-secret-2024"


@pytest.fixture(scope="session", autouse=True)
def rebuild_project():
    shutil.rmtree(BUILD_DIR, ignore_errors=True)

    configure = subprocess.run(
        ["cmake", "-B", "build"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert configure.returncode == 0, (
        "CMake configuration failed:\n" + configure.stdout + configure.stderr
    )

    build = subprocess.run(
        ["cmake", "--build", "build"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, (
        "CMake build failed:\n" + build.stdout + build.stderr
    )


def run_validator(path):
    result = subprocess.run([EXECUTABLE, path], capture_output=True, text=True)
    return result.stdout.strip()


def b64url(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}. Did the build succeed?"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable."


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No clean tokens found in corpus."

    failed_files = []
    for f in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, f)
        output = run_validator(filepath)
        if output != "VALID":
            failed_files.append(f)

    if failed_files:
        msg = f"{len(failed_files)} of {len(clean_files)} clean tokens rejected or modified.\n"
        msg += "Offending files: " + ", ".join(failed_files)
        pytest.fail(msg)


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No evil tokens found in corpus."

    failed_files = []
    for f in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, f)
        output = run_validator(filepath)
        if output != "INVALID":
            failed_files.append(f)

    if failed_files:
        msg = f"{len(failed_files)} of {len(evil_files)} evil tokens bypassed.\n"
        msg += "Offending files: " + ", ".join(failed_files)
        pytest.fail(msg)


def test_fresh_randomized_tokens():
    now = int(time.time())

    valid_payload = {
        "role": "auditor",
        "exp": now + 1800,
        "nonce": secrets.token_hex(16),
    }
    valid = jwt.encode(valid_payload, SECRET, algorithm="HS256")

    second_valid = jwt.encode(
        {
            "role": "auditor",
            "exp": now + 900,
            "nonce": secrets.token_hex(16),
            "id": secrets.randbelow(1_000_000),
        },
        SECRET,
        algorithm="HS256",
    )

    wrong_secret = jwt.encode(
        {"role": "auditor", "exp": now + 1800, "nonce": secrets.token_hex(16)},
        "incorrect-" + secrets.token_hex(16),
        algorithm="HS256",
    )
    expired = jwt.encode(
        {"role": "auditor", "exp": now - 300, "nonce": secrets.token_hex(16)},
        SECRET,
        algorithm="HS256",
    )
    wrong_role = jwt.encode(
        {"role": "admin", "exp": now + 1800, "nonce": secrets.token_hex(16)},
        SECRET,
        algorithm="HS256",
    )
    non_string_role = jwt.encode(
        {"role": ["auditor"], "exp": now + 1800, "nonce": secrets.token_hex(16)},
        SECRET,
        algorithm="HS256",
    )
    wrong_algorithm = jwt.encode(
        {"role": "auditor", "exp": now + 1800, "nonce": secrets.token_hex(16)},
        SECRET,
        algorithm="HS384",
    )

    none_header = {"alg": "none", "typ": "JWT", "nonce": secrets.token_hex(8)}
    none_payload = {
        "role": "auditor",
        "exp": now + 1800,
        "nonce": secrets.token_hex(16),
    }
    none_token = (
        b64url(json.dumps(none_header, separators=(",", ":")).encode())
        + "."
        + b64url(json.dumps(none_payload, separators=(",", ":")).encode())
        + "."
    )

    parts = valid.split(".")
    tampered_payload = dict(valid_payload)
    tampered_payload["nonce"] = secrets.token_hex(16)
    tampered = (
        parts[0]
        + "."
        + b64url(json.dumps(tampered_payload, separators=(",", ":")).encode())
        + "."
        + parts[2]
    )

    cases = [
        (valid, "VALID"),
        (second_valid, "VALID"),
        (wrong_secret, "INVALID"),
        (expired, "INVALID"),
        (wrong_role, "INVALID"),
        (non_string_role, "INVALID"),
        (wrong_algorithm, "INVALID"),
        (none_token, "INVALID"),
        (tampered, "INVALID"),
        ("not-a-jwt-" + secrets.token_hex(12), "INVALID"),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="jwt-check-") as directory:
        written = []
        for token, expected in cases:
            path = os.path.join(directory, uuid.uuid4().hex)
            with open(path, "w", encoding="utf-8") as token_file:
                token_file.write(token)
            written.append((path, expected))

        random.SystemRandom().shuffle(written)
        failures = []
        for path, expected in written:
            actual = run_validator(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))

        assert not failures, "Fresh token validation failures: " + repr(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
